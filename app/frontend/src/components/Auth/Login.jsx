import React, { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { Box, Paper, TextField, Button, Typography, Alert, ToggleButtonGroup, ToggleButton } from '@mui/material';
import { User, Lock, Activity } from 'lucide-react';
import axios from '../../api';
import { useAuth } from '../../context/AuthContext';
import rigLoginImage from '../../assets/ahwr-50-rig-login.png';
import ongcLogo from '../../assets/ongc-logo.png';

const Login = () => {
    const [credentials, setCredentials] = useState({ username: '', password: '' });
    const [error, setError] = useState('');
    const [loading, setLoading] = useState(false);
    const navigate = useNavigate();
    const { login, user } = useAuth();
    const [authInfo, setAuthInfo] = useState(null);
    const [provider, setProvider] = useState('local');   // 'local' | 'domain'

    const domainMode = !!authInfo?.ldapEnabled && provider === 'domain';
    const userLabel = domainMode ? `${authInfo?.domain || 'DOMAIN'}\\username` : 'User ID';

    useEffect(() => {
        axios.get('/api/auth/info').then((r) => setAuthInfo(r.data)).catch(() => {});
    }, []);

    // Already authenticated -> skip the login form.
    useEffect(() => {
        if (user) navigate('/', { replace: true });
    }, [user, navigate]);

    const handleChange = (e) => {
        setCredentials({ ...credentials, [e.target.name]: e.target.value });
    };

    const handleSubmit = async (e) => {
        e.preventDefault();
        setError('');
        setLoading(true);

        try {
            // Use relative path which will be proxied by Vite
            const API_URL = '';
            // In domain mode, qualify a bare username with the domain (DOMAIN\user).
            let username = credentials.username;
            if (domainMode && username && !username.includes('\\') && !username.includes('@') && authInfo?.domain) {
                username = `${authInfo.domain}\\${username}`;
            }
            const res = await axios.post(`${API_URL}/api/login`, { ...credentials, username });

            if (res.data.success) {
                login(res.data.user, res.data.token);
                navigate('/');
            }
        } catch (err) {
            setError(err.response?.data?.message || 'Failed to login. Please check server connection.');
        } finally {
            setLoading(false);
        }
    };

    return (
        <Box
            sx={{
                width: '100%',
                minHeight: '100dvh',
                display: 'flex',
                bgcolor: '#0f172a',
                fontFamily: 'Arial, sans-serif',
                '& .MuiTypography-root, & .MuiButtonBase-root, & .MuiInputBase-root, & .MuiInputLabel-root': { fontFamily: 'Arial, sans-serif' },
                flexDirection: { xs: 'column', md: 'row' }
            }}
        >
            <Box
                sx={{
                    position: 'relative',
                    width: { xs: '100%', md: '50%' },
                    minHeight: { xs: 260, md: '100dvh' },
                    overflow: 'hidden',
                    display: 'flex',
                    alignItems: 'flex-end',
                    justifyContent: 'flex-start',
                    backgroundColor: '#172033'
                }}
            >
                <Box
                    sx={{
                        position: 'absolute',
                        top: { xs: 16, md: 28 },
                        left: { xs: 16, md: 28 },
                        zIndex: 4,
                        width: { xs: 132, md: 168 },
                        p: 1,
                        borderRadius: 1.5,
                        bgcolor: 'rgba(255, 255, 255, 0.96)',
                        boxShadow: '0 6px 22px rgba(2, 8, 23, 0.3)'
                    }}
                >
                    <Box component="img" src={ongcLogo} alt="ONGC" sx={{ display: 'block', width: '100%', height: 'auto' }} />
                </Box>
                <Box
                    component="img"
                    src={rigLoginImage}
                    alt=""
                    aria-hidden="true"
                    sx={{ position: 'absolute', inset: '-18px', width: 'calc(100% + 36px)', height: 'calc(100% + 36px)', objectFit: 'cover', objectPosition: 'center', filter: 'blur(18px)', opacity: 0.48, transform: 'scale(1.04)' }}
                />
                <Box
                    component="img"
                    src={rigLoginImage}
                    alt="AHWR-50 drilling rig"
                    sx={{ position: 'absolute', inset: 0, zIndex: 1, width: '100%', height: '100%', objectFit: 'fill', objectPosition: 'center', boxShadow: '0 0 42px rgba(2, 8, 23, 0.42)' }}
                />
                <Box sx={{ position: 'absolute', inset: 0, zIndex: 2, background: 'linear-gradient(180deg, rgba(2, 8, 23, 0.04) 25%, rgba(2, 8, 23, 0.82) 100%)' }} />
            </Box>

            <Box
                sx={{
                    width: { xs: '100%', md: '50%' },
                    minHeight: { xs: 'auto', md: '100dvh' },
                    display: 'flex',
                    alignItems: 'center',
                    justifyContent: 'center',
                    boxSizing: 'border-box',
                    p: { xs: 2, sm: 4, md: 6 },
                    backgroundImage: 'radial-gradient(circle at 50% 50%, #1e293b 0%, #0f172a 100%)'
                }}
            >
                <Paper
                    elevation={24}
                    sx={{
                        p: { xs: 3, sm: 4 },
                        width: '100%',
                        maxWidth: 444,
                        display: 'flex',
                        flexDirection: 'column',
                        alignItems: 'center',
                        bgcolor: '#404a59',
                        backgroundImage: 'none',
                        backdropFilter: 'blur(10px)',
                        border: '1px solid rgba(255, 255, 255, 0.1)',
                        borderRadius: 4,
                        boxSizing: 'border-box'
                    }}
                >
                    <Box sx={{ mb: 3, display: 'flex', flexDirection: 'column', alignItems: 'center' }}>
                        <Activity size={48} color="#38bdf8" />
                        <Typography variant="h4" sx={{ mt: 2, fontWeight: 'bold', color: '#fff', letterSpacing: 1 }}>
                            AHWR-50 Twin
                        </Typography>
                        <Typography variant="subtitle2" sx={{ color: '#94a3b8' }}>
                            Digital Twin Access
                        </Typography>
                    </Box>

                    {(
                        <Box sx={{ width: '100%', mb: 1 }}>
                            <ToggleButtonGroup
                                value={provider}
                                exclusive
                                fullWidth
                                size="small"
                                onChange={(_e, v) => { if (v) setProvider(v); }}
                                sx={{
                                    '& .MuiToggleButton-root': { color: '#94a3b8', borderColor: '#475569', textTransform: 'none', py: 0.75 },
                                    '& .Mui-selected': { color: '#fff !important', bgcolor: 'rgba(56,189,248,0.18) !important', borderColor: '#38bdf8 !important' }
                                }}
                            >
                                <ToggleButton value="local">Local account</ToggleButton>
                                <ToggleButton value="domain" disabled={!authInfo?.ldapEnabled} sx={{ '&.Mui-disabled': { color: '#94a3b8' } }}>Windows Domain</ToggleButton>
                            </ToggleButtonGroup>
                            {domainMode && (
                                <Typography variant="caption" sx={{ display: 'block', color: '#64748b', mt: 0.5, textAlign: 'center' }}>
                                    Sign in with your {authInfo.domain || 'domain'} account
                                </Typography>
                            )}
                        </Box>
                    )}

                    {error && (
                        <Alert severity="error" sx={{ width: '100%', mb: 2, bgcolor: 'rgba(239, 68, 68, 0.1)', color: '#fca5a5' }}>
                            {error}
                        </Alert>
                    )}

                    <Box component="form" onSubmit={handleSubmit} sx={{ width: '100%' }}>
                        <TextField
                            margin="normal"
                            required
                            fullWidth
                            id="username"
                            label={userLabel}
                            name="username"
                            autoComplete="username"
                            autoFocus
                            value={credentials.username}
                            onChange={handleChange}
                            InputProps={{
                                startAdornment: <User size={20} color="#94a3b8" style={{ marginRight: 10 }} />,
                            }}
                            sx={{
                                '& .MuiOutlinedInput-root': {
                                    color: '#fff',
                                    '& fieldset': { borderColor: '#475569' },
                                    '&:hover fieldset': { borderColor: '#94a3b8' },
                                    '&.Mui-focused fieldset': { borderColor: '#38bdf8' },
                                },
                                '& .MuiInputLabel-root': { color: '#94a3b8' },
                                '& .MuiInputLabel-root.Mui-focused': { color: '#38bdf8' }
                            }}
                        />
                        <TextField
                            margin="normal"
                            required
                            fullWidth
                            name="password"
                            label="Password"
                            type="password"
                            id="password"
                            autoComplete="current-password"
                            value={credentials.password}
                            onChange={handleChange}
                            InputProps={{
                                startAdornment: <Lock size={20} color="#94a3b8" style={{ marginRight: 10 }} />,
                            }}
                            sx={{
                                '& .MuiOutlinedInput-root': {
                                    color: '#fff',
                                    '& fieldset': { borderColor: '#475569' },
                                    '&:hover fieldset': { borderColor: '#94a3b8' },
                                    '&.Mui-focused fieldset': { borderColor: '#38bdf8' },
                                },
                                '& .MuiInputLabel-root': { color: '#94a3b8' },
                                '& .MuiInputLabel-root.Mui-focused': { color: '#38bdf8' }
                            }}
                        />
                        <Button
                            type="submit"
                            fullWidth
                            variant="contained"
                            disabled={loading}
                            sx={{
                                mt: 3,
                                mb: 2,
                                py: 1.5,
                                bgcolor: '#38bdf8',
                                color: '#00111c',
                                '&:hover': { bgcolor: '#0284c7' },
                                fontWeight: 'bold'
                            }}
                        >
                            {loading ? 'Authenticating...' : 'Sign In'}
                        </Button>
                    </Box>
                </Paper>
            </Box>
        </Box>
    );
};

export default Login;
