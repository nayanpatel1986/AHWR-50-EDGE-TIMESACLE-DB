'use strict';
// Active Directory / LDAP authentication (Windows domain login).
//
// Verifies credentials by binding to the Domain Controller over LDAP(S) and
// maps AD security groups -> app roles. Two modes:
//   * service-account search:  bind LDAP_BIND_DN, search for the user, then
//     re-bind as the user to verify the password (recommended for AD).
//   * direct bind:             bind directly as user@domain (UPN), then read
//     group membership on the same connection (no service account needed).
// Disabled unless AUTH_MODE includes ldap and LDAP_URL is set.
let Client;
try { ({ Client } = require('ldapts')); } catch { Client = null; }

const bool = (v, def = false) => (v === undefined ? def : /^(1|true|yes)$/i.test(String(v)));
const list = (s) => (s || '').split(',').map((x) => x.trim().toLowerCase()).filter(Boolean);

const cfg = {
    mode: (process.env.AUTH_MODE || 'local').toLowerCase(),       // local | ldap | both
    url: process.env.LDAP_URL || '',                              // ldap://dc:389 or ldaps://dc:636
    bindDN: process.env.LDAP_BIND_DN || '',
    bindPassword: process.env.LDAP_BIND_PASSWORD || '',
    searchBase: process.env.LDAP_SEARCH_BASE || '',
    searchFilter: process.env.LDAP_SEARCH_FILTER || '(|(sAMAccountName={username})(userPrincipalName={username}))',
    domain: process.env.LDAP_DOMAIN || '',                        // e.g. corp.example.com (used to build UPN)
    defaultRole: (process.env.LDAP_DEFAULT_ROLE || 'viewer').toLowerCase(),
    groupAdmin: list(process.env.LDAP_ROLE_ADMIN),
    groupOperator: list(process.env.LDAP_ROLE_OPERATOR),
    groupViewer: list(process.env.LDAP_ROLE_VIEWER),
    startTLS: bool(process.env.LDAP_STARTTLS),
    // TLS cert validation: ON by default; set LDAP_TLS_REJECT_UNAUTHORIZED=false only for self-signed lab DCs.
    rejectUnauthorized: !/^(0|false|no)$/i.test(process.env.LDAP_TLS_REJECT_UNAUTHORIZED || ''),
    timeout: Number(process.env.LDAP_TIMEOUT_MS || 8000),
};

function configurationIssue() {
    if (cfg.mode !== 'ldap' && cfg.mode !== 'both') return 'disabled';
    if (!Client) return 'client_unavailable';
    if (!cfg.url || !cfg.searchBase) return 'missing_directory_settings';
    if (!/^ldaps:\/\//i.test(cfg.url) && !(cfg.startTLS && /^ldap:\/\//i.test(cfg.url))) return 'secure_connection_required';
    if (cfg.bindDN && !cfg.bindPassword) return 'missing_bind_password';
    if (!cfg.bindDN && !cfg.domain.includes('.')) return 'domain_dns_name_required';
    return null;
}

const ldapEnabled = () => configurationIssue() === null;

const info = () => ({
    authMode: cfg.mode,
    localEnabled: cfg.mode === 'local' || cfg.mode === 'both',
    ldapEnabled: ldapEnabled(),
    domain: cfg.domain || null,
    domainConfiguration: cfg.mode === 'local' ? 'off' : ldapEnabled() ? 'configured' : 'incomplete',
});

// RFC 4515 escape for a value placed inside a search filter (prevents LDAP injection).
const escapeFilter = (v) => String(v).replace(/[\\*()\x00]/g, (c) => '\\' + c.charCodeAt(0).toString(16).padStart(2, '0'));

// Normalize DOMAIN\user, user@domain, or bare user into a sAMAccountName + UPN.
function parseUsername(raw) {
    const u = String(raw || '').trim();
    let sam = u;
    let upn = u;
    if (u.includes('\\')) sam = u.split('\\').pop();
    if (u.includes('@')) { sam = u.split('@')[0]; upn = u; }
    else if (cfg.domain && cfg.domain.includes('.')) upn = `${sam}@${cfg.domain}`;
    return { sam, upn, raw: u };
}

function newClient() {
    const opts = { url: cfg.url, timeout: cfg.timeout, connectTimeout: cfg.timeout };
    // tlsOptions only applies to secure transports (ldaps:// or StartTLS). Passing it
    // on a plain ldap:// URL makes some ldapts versions attempt a TLS handshake and fail.
    if (/^ldaps:/i.test(cfg.url) || cfg.startTLS) opts.tlsOptions = { rejectUnauthorized: cfg.rejectUnauthorized };
    return new Client(opts);
}

// Group CN from a DN ("CN=RigAdmins,OU=Groups,..." -> "rigadmins"); already lowercased.
const groupCn = (dn) => { const m = /^cn=([^,]+)/.exec(dn); return m ? m[1].trim() : null; };

function mapRole(memberOf) {
    const groups = (Array.isArray(memberOf) ? memberOf : memberOf ? [memberOf] : []).map((g) => String(g).toLowerCase());
    // Exact match on the full DN or the group's own CN only. A substring match let
    // e.g. "CN=RigAdmins-ReadOnly" or "OU=Admin Accounts" grant the admin role.
    const inAny = (names) => names.some((n) => groups.some((g) => g === n || groupCn(g) === n));
    if (cfg.groupAdmin.length && inAny(cfg.groupAdmin)) return 'admin';
    if (cfg.groupOperator.length && inAny(cfg.groupOperator)) return 'operator';
    if (cfg.groupViewer.length && inAny(cfg.groupViewer)) return 'viewer';
    return cfg.defaultRole;
}

const ATTRS = ['dn', 'distinguishedName', 'sAMAccountName', 'userPrincipalName', 'displayName', 'cn', 'memberOf'];

// Authenticate against the directory. Returns { username, displayName, role, groups }
// on success; throws on any failure (bad credentials, not found, unreachable).
async function authenticate(rawUsername, password) {
    if (!ldapEnabled()) throw new Error('LDAP not enabled');
    if (!password) throw new Error('Password required');
    const { sam, upn } = parseUsername(rawUsername);
    let entry = null;

    if (cfg.bindDN) {
        // --- service-account search, then verify by re-binding as the user ---
        const client = newClient();
        try {
            if (cfg.startTLS) await client.startTLS({ rejectUnauthorized: cfg.rejectUnauthorized });
            await client.bind(cfg.bindDN, cfg.bindPassword);
            const filter = cfg.searchFilter.replace(/\{username\}/g, escapeFilter(sam));
            const { searchEntries } = await client.search(cfg.searchBase, { scope: 'sub', filter, attributes: ATTRS });
            entry = searchEntries[0];
        } finally { try { await client.unbind(); } catch { /* ignore */ } }
        if (!entry) throw new Error('User not found in directory');

        const userDn = entry.dn || entry.distinguishedName;
        const uc = newClient();
        try {
            if (cfg.startTLS) await uc.startTLS({ rejectUnauthorized: cfg.rejectUnauthorized });
            await uc.bind(userDn, password); // throws on wrong password
        } finally { try { await uc.unbind(); } catch { /* ignore */ } }
    } else {
        // --- direct UPN bind (no service account); read groups on same connection ---
        const client = newClient();
        try {
            if (cfg.startTLS) await client.startTLS({ rejectUnauthorized: cfg.rejectUnauthorized });
            await client.bind(upn, password); // throws on wrong password
            if (cfg.searchBase) {
                const filter = cfg.searchFilter.replace(/\{username\}/g, escapeFilter(sam));
                const { searchEntries } = await client.search(cfg.searchBase, { scope: 'sub', filter, attributes: ATTRS });
                entry = searchEntries[0];
            }
        } finally { try { await client.unbind(); } catch { /* ignore */ } }
        if (!entry) entry = { sAMAccountName: sam, displayName: sam, memberOf: [] };
    }

    const username = String(entry.sAMAccountName || sam);
    const displayName = String(entry.displayName || entry.cn || username);
    const role = mapRole(entry.memberOf);
    const groups = Array.isArray(entry.memberOf) ? entry.memberOf : entry.memberOf ? [entry.memberOf] : [];
    return { username, displayName, role, groups };
}

module.exports = { ldapEnabled, info, authenticate, parseUsername, mapRole, _cfg: cfg };
