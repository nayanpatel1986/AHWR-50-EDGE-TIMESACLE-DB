import React, { useState, useEffect } from 'react';
import { Grid, Paper, Typography, Box, Divider, useTheme } from '@mui/material';
import { getLatestRigData, isLiveRigPayload, socket } from '../../socket';
import EdrView from '../EDR/EdrView';

// ---- Local reusable presentational helpers (flatter/denser than analog dials) ----

const ValueTile = ({ label, value, unit, decimals = 0, color = 'primary.main', min = 0, max, warn, crit, sub }) => {
    const num = Number(value);
    const has = Number.isFinite(num);
    const display = has ? num.toFixed(decimals) : '--';

    let accent = color;
    let ratio = null;
    if (has && Number.isFinite(max) && max > min) {
        ratio = Math.min(Math.max((num - min) / (max - min), 0), 1);
        const wr = warn != null ? (warn - min) / (max - min) : null;
        const cr = crit != null ? (crit - min) / (max - min) : null;
        if (cr != null && ratio >= cr) accent = '#ef4444';
        else if (wr != null && ratio >= wr) accent = '#fbbf24';
    }

    return (
        <Paper sx={{ p: 1.5, bgcolor: 'background.paper', border: '1px solid', borderColor: 'divider', borderRadius: 2, height: '100%', display: 'flex', flexDirection: 'column' }}>
            <Typography variant="caption" sx={{ color: 'text.secondary', fontWeight: 700, letterSpacing: 0.4, textTransform: 'uppercase', fontSize: '0.66rem' }} noWrap>{label}</Typography>
            <Box sx={{ display: 'flex', alignItems: 'baseline', gap: 0.5, mt: 0.25 }}>
                <Typography sx={{ color: accent, fontWeight: 800, fontSize: '1.7rem', lineHeight: 1.05 }}>{display}</Typography>
                {unit && <Typography sx={{ color: 'text.secondary', fontWeight: 600, fontSize: '0.78rem' }}>{unit}</Typography>}
            </Box>
            {ratio != null && (
                <Box sx={{ mt: 'auto', pt: 1 }}>
                    <Box sx={{ height: 5, borderRadius: 3, bgcolor: 'action.hover', overflow: 'hidden' }}>
                        <Box sx={{ width: `${ratio * 100}%`, height: '100%', bgcolor: accent, borderRadius: 3, transition: 'width .4s ease' }} />
                    </Box>
                </Box>
            )}
            {sub && <Typography variant="caption" sx={{ color: 'text.secondary', mt: ratio != null ? 0.5 : 'auto', pt: ratio != null ? 0 : 1, fontSize: '0.62rem' }} noWrap>{sub}</Typography>}
        </Paper>
    );
};

const StatusChip = ({ label, value, mapping, dense = false }) => {
    const active = mapping[value] || { text: '---', color: '#64748b' };
    return (
        <Box sx={{ textAlign: 'center', px: dense ? 0 : 1 }}>
            <Typography variant="caption" sx={{ color: 'text.secondary', display: 'block', mb: 0.5, fontSize: '0.62rem', fontWeight: 700 }}>{label.toUpperCase()}</Typography>
            <Box sx={{
                bgcolor: `${active.color}1f`,
                color: active.color,
                border: `1px solid ${active.color}`,
                px: 1.25, py: 0.5, borderRadius: 1,
                fontWeight: 'bold', fontSize: dense ? '0.7rem' : '0.8rem', whiteSpace: 'nowrap'
            }}>
                {active.text}
            </Box>
        </Box>
    );
};

const SectionTitle = ({ children }) => (
    <Typography sx={{ color: 'text.secondary', fontSize: '0.7rem', fontWeight: 800, letterSpacing: 0.8, textTransform: 'uppercase', mb: 1 }}>{children}</Typography>
);

// EDR side-strip config — all HPU catalog channels, including status fields.
const EDR_CHANNELS = [
    'hpu.aux_pressure',
    'hpu.discharge_pressure',
    'hpu.gate_valve',
    'hpu.htd_pump1_flow_sp',
    'hpu.htd_pump1_flow',
    'hpu.htd_pump1_press_sp',
    'hpu.htd_pump1_press',
    'hpu.htd_pump1_status',
    'hpu.htd_pump2_flow_sp',
    'hpu.htd_pump2_flow',
    'hpu.htd_pump2_press_sp',
    'hpu.htd_pump2_press',
    'hpu.htd_pump2_status',
    'hpu.pdw_pump_flow_sp',
    'hpu.pdw_pump_flow',
    'hpu.pdw_pump_press_sp',
    'hpu.pdw_pump_press',
    'hpu.pdw_pump_status',
    'hpu.oil_filter_1',
    'hpu.oil_filter_2',
    'hpu.oil_filter_3',
    'hpu.oil_filter_4',
    'hpu.oil_filter_5',
    'hpu.oil_filter_6',
    'hpu.oil_filter_7',
    'hpu.oil_filter_8',
    'hpu.oil_level_status',
    'hpu.oil_temp_status',
    'hpu.op_mode',
    'hpu.pilot_pressure',
    'hpu.pilot_status',
    'hpu.run_hours',
    'hpu.status',
    'hpu.oil_level',
    'hpu.oil_temp'
];
const EDR_STRIPS = [
    {
        title: 'HPU',
        pens: [
            { channelId: 'hpu.discharge_pressure', color: '#38bdf8', min: 0, max: 300, enabled: true },
            { channelId: 'hpu.oil_temp', color: '#f97316', min: 0, max: 120, enabled: true },
            { channelId: 'hpu.oil_level', color: '#22d3ee', min: 0, max: 100, enabled: true }
        ]
    }
];

export default function HpuDashboard() {
    const theme = useTheme();
    const surface = theme.palette.background.paper;
    const inset = theme.palette.background.default;
    const border = theme.palette.divider;
    const [data, setData] = useState({});

    useEffect(() => {
        const cached = getLatestRigData();
        if (isLiveRigPayload(cached) && cached.hpu) setData(cached.hpu);

        const handler = (newData) => {
            if (!isLiveRigPayload(newData)) { setData({}); return; }
            if (newData.hpu) setData(newData.hpu);
        };
        socket.on('rig_data', handler);
        const onDisconnect = () => setData({});
        socket.on('disconnect', onDisconnect);
        return () => { socket.off('rig_data', handler); socket.off('disconnect', onDisconnect); };
    }, []);

    const statusMapping = {
        0: { text: 'OFF', color: '#64748b' },
        1: { text: 'ON IDLE', color: '#38bdf8' },
        2: { text: 'ON', color: '#4ade80' }
    };

    const pilotMapping = {
        0: { text: 'OFF', color: '#64748b' },
        1: { text: 'ON', color: '#4ade80' },
        2: { text: 'FAULT', color: '#ef4444' }
    };

    const opModeMapping = {
        0: { text: 'UNKNOWN', color: '#64748b' },
        1: { text: 'DRILLING', color: '#4ade80' },
        2: { text: 'RIG UP', color: '#38bdf8' }
    };

    const oilStatusMapping = {
        0: { text: 'OK', color: '#4ade80' },
        1: { text: 'LOW', color: '#fbbf24' },
        2: { text: 'HIGH', color: '#f97316' },
        3: { text: 'HH/CRIT', color: '#ef4444' },
        4: { text: 'HH/CRIT', color: '#ef4444' }
    };

    const pumpStatusMapping = {
        0: { text: 'NOT READY', color: '#f97316' },
        1: { text: 'READY', color: '#4ade80' },
        2: { text: 'ENABLE', color: '#38bdf8' }
    };

    const gateMapping = {
        0: { text: 'CLOSED', color: '#ef4444' },
        1: { text: 'OPEN', color: '#4ade80' }
    };

    const panelSx = { p: 1.75, bgcolor: surface, height: '100%', borderRadius: 2, border: `1px solid ${border}` };

    // Hydraulic pump rendered as a compact mini-card (status chip + flow/press tile-row).
    const PumpCard = ({ title, statusKey, flowKey, pressKey }) => {
        const active = pumpStatusMapping[data[statusKey]] || { text: '---', color: '#64748b' };
        return (
            <Box sx={{ p: 1.25, bgcolor: inset, borderRadius: 1.5, border: `1px solid ${border}`, height: '100%', display: 'flex', flexDirection: 'column', justifyContent: 'space-between' }}>
                <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', mb: 1, gap: 1 }}>
                    <Typography variant="caption" sx={{ color: 'text.primary', fontWeight: 800, letterSpacing: 0.4 }}>{title}</Typography>
                    <Box sx={{ bgcolor: `${active.color}1f`, color: active.color, border: `1px solid ${active.color}`, px: 1, py: 0.2, borderRadius: 1, fontWeight: 'bold', fontSize: '0.68rem', textAlign: 'center', minWidth: 60 }}>{active.text}</Box>
                </Box>
                <Box sx={{ display: 'flex', justifyContent: 'space-between', mt: 'auto' }}>
                    <Box>
                        <Typography variant="caption" sx={{ color: '#64748b', fontSize: '0.6rem', display: 'block' }}>FLOW</Typography>
                        <Typography sx={{ color: 'text.primary', fontWeight: 700, fontSize: '0.9rem' }}>{Number(data[flowKey] || 0).toFixed(2)} %</Typography>
                    </Box>
                    <Box sx={{ textAlign: 'right' }}>
                        <Typography variant="caption" sx={{ color: '#64748b', fontSize: '0.6rem', display: 'block' }}>PRESS</Typography>
                        <Typography sx={{ color: 'text.primary', fontWeight: 700, fontSize: '0.9rem' }}>{Number(data[pressKey] || 0).toFixed(2)} bar</Typography>
                    </Box>
                </Box>
            </Box>
        );
    };

    return (
        <Box sx={{ display: 'flex', flexWrap: 'wrap', alignItems: 'stretch', gap: 2 }}>
            {/* Main content */}
            <Box sx={{ flex: '1 1 560px', minWidth: 0 }}>
                <Grid container spacing={2}>
                    {/* Status header */}
                    <Grid item xs={12}>
                        <Paper sx={{ p: 1.75, bgcolor: surface, border: `1px solid ${border}`, display: 'flex', alignItems: 'center', flexWrap: 'wrap', gap: 2 }}>
                            <StatusChip label="System Status" value={data.status} mapping={statusMapping} />
                            <Divider orientation="vertical" flexItem sx={{ borderColor: border }} />
                            <StatusChip label="Operating Mode" value={data.op_mode} mapping={opModeMapping} />
                            <Divider orientation="vertical" flexItem sx={{ borderColor: border }} />
                            <StatusChip label="Pilot Status" value={data.pilot_status} mapping={pilotMapping} />
                            <Divider orientation="vertical" flexItem sx={{ borderColor: border }} />
                            <StatusChip label="Gate Valve" value={data.gate_valve} mapping={gateMapping} />
                            <Box sx={{ ml: 'auto', textAlign: 'right', pr: 1 }}>
                                <Typography variant="caption" sx={{ color: 'text.secondary', display: 'block', fontSize: '0.62rem', fontWeight: 700 }}>RUN HOURS</Typography>
                                <Typography variant="h6" sx={{ color: 'primary.main', fontWeight: 'bold' }}>{Number(data.run_hours || 0).toFixed(2)} <span style={{ fontSize: '0.55em', color: '#64748b' }}>HRS</span></Typography>
                            </Box>
                        </Paper>
                    </Grid>

                    {/* PRESSURES */}
                    <Grid item xs={12}>
                        <SectionTitle>Pressures</SectionTitle>
                        <Grid container spacing={1.5}>
                            <Grid item xs={6} sm={4} md={3}>
                                <ValueTile label="Discharge Press" value={data.discharge_pressure} unit="bar" decimals={1} color="#38bdf8" min={0} max={350} warn={280} crit={320} />
                            </Grid>
                            <Grid item xs={6} sm={4} md={3}>
                                <ValueTile label="Aux Pressure" value={data.aux_pressure} unit="bar" decimals={1} color="#a78bfa" min={0} max={250} warn={210} crit={235} />
                            </Grid>
                            <Grid item xs={6} sm={4} md={3}>
                                <ValueTile label="Pilot LS Press" value={data.pilot_pressure} unit="bar" decimals={2} color="#22d3ee" min={0} max={50} />
                            </Grid>
                        </Grid>
                    </Grid>

                    {/* OIL */}
                    <Grid item xs={12}>
                        <SectionTitle>Hydraulic Oil</SectionTitle>
                        <Grid container spacing={1.5}>
                            <Grid item xs={6} sm={4} md={3}>
                                <ValueTile label="Oil Temp" value={data.oil_temp} unit="°C" decimals={1} color="#f97316" min={0} max={100} warn={70} crit={85} />
                            </Grid>
                            <Grid item xs={6} sm={4} md={3}>
                                <ValueTile label="Oil Level" value={data.oil_level} unit="%" decimals={1} color="#22d3ee" min={0} max={100} />
                            </Grid>
                            <Grid item xs={6} sm={4} md={3}>
                                <Paper sx={{ p: 1.5, bgcolor: 'background.paper', border: '1px solid', borderColor: 'divider', borderRadius: 2, height: '100%', display: 'flex', flexDirection: 'column', justifyContent: 'center' }}>
                                    <StatusChip label="Temp Status" value={data.oil_temp_status} mapping={oilStatusMapping} />
                                </Paper>
                            </Grid>
                            <Grid item xs={6} sm={4} md={3}>
                                <Paper sx={{ p: 1.5, bgcolor: 'background.paper', border: '1px solid', borderColor: 'divider', borderRadius: 2, height: '100%', display: 'flex', flexDirection: 'column', justifyContent: 'center' }}>
                                    <StatusChip label="Level Status" value={data.oil_level_status} mapping={oilStatusMapping} />
                                </Paper>
                            </Grid>
                        </Grid>
                    </Grid>

                    {/* OIL FILTERS */}
                    <Grid item xs={12} md={5}>
                        <Paper sx={panelSx}>
                            <SectionTitle>Oil Filters</SectionTitle>
                            <Grid container spacing={1}>
                                {[1, 2, 3, 4, 5, 6, 7, 8].map(num => {
                                    const ok = data[`oil_filter_${num}`] !== 0 && data[`oil_filter_${num}`] != null;
                                    const c = ok ? '#4ade80' : '#ef4444';
                                    return (
                                        <Grid item xs={6} sm={3} key={`filter-${num}`}>
                                            <Box sx={{ p: 0.75, bgcolor: inset, borderRadius: 1, textAlign: 'center', border: `1px solid ${c}55` }}>
                                                <Typography variant="caption" sx={{ color: 'text.secondary', display: 'block', fontSize: '0.6rem', fontWeight: 700 }}>FILTER {num}</Typography>
                                                <Typography sx={{ color: c, fontWeight: 'bold', fontSize: '0.72rem' }}>{ok ? 'OK' : 'CLOGGED'}</Typography>
                                            </Box>
                                        </Grid>
                                    );
                                })}
                            </Grid>
                        </Paper>
                    </Grid>

                    {/* HYDRAULIC PUMPS */}
                    <Grid item xs={12} md={7}>
                        <Paper sx={panelSx}>
                            <SectionTitle>Hydraulic Pumps</SectionTitle>
                            <Grid container spacing={1.25} sx={{ height: 'calc(100% - 24px)' }}>
                                <Grid item xs={12} sm={4}>
                                    <PumpCard title="PUMP-3 PDW" statusKey="pdw_pump_status" flowKey="pdw_pump_flow" pressKey="pdw_pump_press" />
                                </Grid>
                                <Grid item xs={12} sm={4}>
                                    <PumpCard title="HTD PUMP-2" statusKey="htd_pump1_status" flowKey="htd_pump1_flow" pressKey="htd_pump1_press" />
                                </Grid>
                                <Grid item xs={12} sm={4}>
                                    <PumpCard title="HTD PUMP-4" statusKey="htd_pump2_status" flowKey="htd_pump2_flow" pressKey="htd_pump2_press" />
                                </Grid>
                            </Grid>
                        </Paper>
                    </Grid>
                </Grid>
            </Box>

            {/* Persistent EDR side strip */}
            <Box
                sx={{
                    flex: { xs: '1 1 100%', lg: '0 0 400px' },
                    width: { xs: '100%', lg: 400 },
                    minHeight: { xs: 420, lg: 560 },
                    height: { lg: 'calc(100vh - 220px)' },
                    display: 'flex',
                    flexDirection: 'column'
                }}
            >
                <Paper sx={{ flex: 1, minHeight: 0, p: 1.25, bgcolor: surface, border: `1px solid ${border}`, borderRadius: 2, display: 'flex', flexDirection: 'column' }}>
                    <Typography sx={{ color: 'text.secondary', fontSize: '0.72rem', fontWeight: 800, letterSpacing: 0.6, textTransform: 'uppercase', mb: 0.75 }}>
                        HPU Trends
                    </Typography>
                    <Box sx={{ flex: 1, minHeight: 0 }}>
                        <EdrView mode="compact" storageKey="edr-hpu-1" defaultStrips={EDR_STRIPS} channels={EDR_CHANNELS} />
                    </Box>
                </Paper>
            </Box>
        </Box>
    );
}
