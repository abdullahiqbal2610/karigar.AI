const express = require('express');
const http = require('http');
const { Server } = require('socket.io');
const cors = require('cors');
const { spawn } = require('child_process');
const path = require('path');

// ─── App & Server Setup ────────────────────────────────────────────────────────
const app = express();
const httpServer = http.createServer(app);

// ─── Socket.io Initialization ──────────────────────────────────────────────────
const io = new Server(httpServer, {
    cors: {
        origin: '*',          // Allow all origins (tighten in production)
        methods: ['GET', 'POST'],
    },
});

// ─── Middleware ────────────────────────────────────────────────────────────────
app.use(cors());
app.use(express.json());

// ─── Track connected sockets ───────────────────────────────────────────────────
io.on('connection', (socket) => {
    console.log(`[Socket.io] Client connected: ${socket.id}`);

    socket.on('disconnect', () => {
        console.log(`[Socket.io] Client disconnected: ${socket.id}`);
    });
});

// ─── Helper: broadcast to all connected clients ────────────────────────────────
const broadcast = (event, data) => {
    io.emit(event, data);
};

// ─── POST /api/request-service ─────────────────────────────────────────────────
app.post('/api/request-service', (req, res) => {
    const { prompt, language } = req.body;

    if (!prompt) {
        return res.status(400).json({ error: 'Missing required field: prompt' });
    }

    console.log(`[API] Received request — prompt: "${prompt}", language: "${language}"`);

    // Step 1: Immediately notify the client that we are analysing the request
    broadcast('status_update', 'Analyzing request...');

    // Path to the Python coordinator (relative to this file → ../ai_agents/coordinator.py)
    const coordinatorPath = path.resolve(__dirname, '..', 'ai_agents', 'coordinator.py');

    // Spawn the Python process, forwarding prompt (and optionally language) as args
    const pythonArgs = [coordinatorPath, prompt];
    if (language) pythonArgs.push(language);

    const pythonProcess = spawn('python', pythonArgs, {
        env: { ...process.env, PYTHONIOENCODING: 'utf-8' }
    });

    // Step 2: While Python is busy, emit the secondary status
    broadcast('status_update', 'Matching with nearby technicians...');

    let stdoutBuffer = '';
    let stderrBuffer = '';

    pythonProcess.stdout.on('data', (chunk) => {
        stdoutBuffer += chunk.toString();
    });

    pythonProcess.stderr.on('data', (chunk) => {
        stderrBuffer += chunk.toString();
        console.warn(`[Python STDERR] ${chunk.toString().trim()}`);
    });

    pythonProcess.on('close', (code) => {
        if (code !== 0) {
            console.error(`[Python] Process exited with code ${code}`);
            console.error(`[Python STDERR] ${stderrBuffer}`);
            broadcast('status_update', 'An error occurred while processing your request.');
            return res.status(500).json({
                error: 'AI coordinator failed',
                details: stderrBuffer.trim() || `Exit code: ${code}`,
            });
        }

        try {
            const result = JSON.parse(stdoutBuffer.trim());
            console.log('[Python] Result parsed successfully:', result);
            broadcast('status_update', 'Request processed successfully!');
            return res.status(200).json(result);
        } catch (parseErr) {
            console.error('[Python] Failed to parse JSON output:', stdoutBuffer);
            broadcast('status_update', 'Failed to parse AI response.');
            return res.status(500).json({
                error: 'Failed to parse AI coordinator output',
                raw: stdoutBuffer.trim(),
            });
        }
    });

    pythonProcess.on('error', (err) => {
        console.error('[Python] Failed to spawn process:', err.message);
        broadcast('status_update', 'Failed to start AI coordinator.');
        return res.status(500).json({
            error: 'Failed to spawn Python process',
            details: err.message,
        });
    });
});

// ─── Health Check ──────────────────────────────────────────────────────────────
app.get('/health', (_req, res) => res.json({ status: 'ok' }));

// ─── Start Server ──────────────────────────────────────────────────────────────
const PORT = process.env.PORT || 3000;
httpServer.listen(PORT, () => {
    console.log(`[Server] Karigar.AI backend running on http://localhost:${PORT}`);
});
