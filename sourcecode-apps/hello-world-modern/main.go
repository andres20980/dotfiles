/*
Enhanced Hello World with Prometheus metrics and structured logging
GitOps Demo Application
*/

package main

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"runtime"
	"strings"
	"sync"
	"time"

	"github.com/gorilla/mux"
)

var (
	// Simple metrics without external dependencies
	requestCount      int64
	requestCountMutex sync.RWMutex
	
	guestbookEntries      []string
	guestbookEntriesMutex sync.RWMutex
	
	startTime = time.Now()
)

// Metrics structure for JSON response
type Metrics struct {
	HTTPRequestsTotal   int64   `json:"http_requests_total"`
	GuestbookEntries    int     `json:"guestbook_entries_total"`
	UptimeSeconds      float64 `json:"uptime_seconds"`
	GoRoutines         int     `json:"go_routines"`
	MemoryUsageMB      float64 `json:"memory_usage_mb"`
	Version            string  `json:"version"`
	GoVersion          string  `json:"go_version"`
}

// Health check response
type Health struct {
	Status    string    `json:"status"`
	Timestamp time.Time `json:"timestamp"`
	Uptime    string    `json:"uptime"`
	Version   string    `json:"version"`
}

// Guestbook entry structure  
type GuestbookEntry struct {
	Message   string    `json:"message"`
	Timestamp time.Time `json:"timestamp"`
	ID        int       `json:"id"`
}

// Simple middleware to count requests
func metricsMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		requestCountMutex.Lock()
		requestCount++
		requestCountMutex.Unlock()
		
		log.Printf("REQUEST: %s %s from %s", r.Method, r.URL.Path, r.RemoteAddr)
		next.ServeHTTP(w, r)
	})
}

func homeHandler(w http.ResponseWriter, r *http.Request) {
	html := `
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Hello World Modern - GitOps Demo</title>
    <style>
        body { font-family: -apple-system,BlinkMacSystemFont,Segoe UI,Roboto,sans-serif; margin: 40px auto; max-width: 650px; line-height: 1.6; color: #444; }
        .header { text-align: center; margin-bottom: 40px; }
        .metrics-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 20px; margin: 20px 0; }
        .metric-card { background: #f5f5f5; padding: 15px; border-radius: 8px; text-align: center; }
        .metric-value { font-size: 2em; font-weight: bold; color: #2563eb; }
        .metric-label { font-size: 0.9em; color: #666; }
        .guestbook { margin: 30px 0; }
        .entry { background: #e5e7eb; padding: 10px; margin: 5px 0; border-radius: 4px; }
        .links { text-align: center; margin: 20px 0; }
        .links a { margin: 0 10px; color: #2563eb; text-decoration: none; }
        .links a:hover { text-decoration: underline; }
        input[type="text"] { width: 70%; padding: 8px; margin-right: 10px; }
        button { padding: 8px 15px; background: #2563eb; color: white; border: none; border-radius: 4px; cursor: pointer; }
    </style>
</head>
<body>
    <div class="header">
        <h1>🚀 Hello World Modern</h1>
        <h3>GitOps Demo with Observability</h3>
    </div>
    
    <div class="metrics-grid">
        <div class="metric-card">
            <div class="metric-value" id="requests">-</div>
            <div class="metric-label">HTTP Requests</div>
        </div>
        <div class="metric-card">
            <div class="metric-value" id="entries">-</div>
            <div class="metric-label">Guestbook Entries</div>
        </div>
        <div class="metric-card">
            <div class="metric-value" id="uptime">-</div>
            <div class="metric-label">Uptime (seconds)</div>
        </div>
        <div class="metric-card">
            <div class="metric-value" id="memory">-</div>
            <div class="metric-label">Memory (MB)</div>
        </div>
    </div>
    
    <div class="guestbook">
        <h3>📝 Guestbook</h3>
        <div>
            <input type="text" id="messageInput" placeholder="Enter your message...">
            <button onclick="addEntry()">Add Message</button>
        </div>
        <div id="entries-list"></div>
    </div>
    
    <div class="links">
        <a href="/health">Health Check</a> |
        <a href="/metrics">Metrics JSON</a> |
        <a href="/env">Environment</a> |
        <a href="/info">System Info</a>
    </div>

    <script>
        function updateMetrics() {
            fetch('/metrics')
                .then(response => response.json())
                .then(data => {
                    document.getElementById('requests').textContent = data.http_requests_total;
                    document.getElementById('entries').textContent = data.guestbook_entries_total;
                    document.getElementById('uptime').textContent = Math.round(data.uptime_seconds);
                    document.getElementById('memory').textContent = data.memory_usage_mb.toFixed(1);
                });
        }

        function loadEntries() {
            fetch('/api/guestbook')
                .then(response => response.json())
                .then(data => {
                    const container = document.getElementById('entries-list');
                    container.innerHTML = '';
                    data.forEach(entry => {
                        const div = document.createElement('div');
                        div.className = 'entry';
                        div.innerHTML = '<strong>#' + entry.id + '</strong> ' + entry.message + 
                                       ' <small>(' + new Date(entry.timestamp).toLocaleString() + ')</small>';
                        container.appendChild(div);
                    });
                });
        }

        function addEntry() {
            const input = document.getElementById('messageInput');
            const message = input.value.trim();
            if (!message) return;

            fetch('/api/guestbook', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ message: message })
            })
            .then(() => {
                input.value = '';
                loadEntries();
                updateMetrics();
            });
        }

        // Auto refresh every 5 seconds
        setInterval(() => {
            updateMetrics();
            loadEntries();
        }, 5000);

        // Initial load
        updateMetrics();
        loadEntries();
    </script>
</body>
</html>`
	
	w.Header().Set("Content-Type", "text/html")
	fmt.Fprint(w, html)
}

func metricsHandler(w http.ResponseWriter, r *http.Request) {
	// Check if Prometheus format is requested
	accept := r.Header.Get("Accept")
	if strings.Contains(accept, "text/plain") || r.URL.Query().Get("format") == "prometheus" {
		// Return Prometheus format
		metricsPrometheusHandler(w, r)
		return
	}
	
	// Default JSON format for UI
	requestCountMutex.RLock()
	currentRequests := requestCount
	requestCountMutex.RUnlock()

	guestbookEntriesMutex.RLock()
	entriesCount := len(guestbookEntries)
	guestbookEntriesMutex.RUnlock()

	// Get memory stats
	var m runtime.MemStats
	runtime.ReadMemStats(&m)
	
	uptime := time.Since(startTime).Seconds()
	
	metrics := Metrics{
		HTTPRequestsTotal:  currentRequests,
		GuestbookEntries:   entriesCount,
		UptimeSeconds:     uptime,
		GoRoutines:        runtime.NumGoroutine(),
		MemoryUsageMB:     float64(m.Alloc) / 1024 / 1024,
		Version:           "2.0.0",
		GoVersion:         runtime.Version(),
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(metrics)
}

func metricsPrometheusHandler(w http.ResponseWriter, r *http.Request) {
	requestCountMutex.RLock()
	currentRequests := requestCount
	requestCountMutex.RUnlock()

	guestbookEntriesMutex.RLock()
	entriesCount := len(guestbookEntries)
	guestbookEntriesMutex.RUnlock()

	// Get memory stats
	var m runtime.MemStats
	runtime.ReadMemStats(&m)
	
	uptime := time.Since(startTime).Seconds()
	
	// Prometheus format
	w.Header().Set("Content-Type", "text/plain")
	fmt.Fprintf(w, "# HELP http_requests_total Total number of HTTP requests\n")
	fmt.Fprintf(w, "# TYPE http_requests_total counter\n")
	fmt.Fprintf(w, "http_requests_total %d\n", currentRequests)
	
	fmt.Fprintf(w, "# HELP guestbook_entries_total Total number of guestbook entries\n")
	fmt.Fprintf(w, "# TYPE guestbook_entries_total gauge\n")
	fmt.Fprintf(w, "guestbook_entries_total %d\n", entriesCount)
	
	fmt.Fprintf(w, "# HELP uptime_seconds Application uptime in seconds\n")
	fmt.Fprintf(w, "# TYPE uptime_seconds gauge\n")
	fmt.Fprintf(w, "uptime_seconds %.2f\n", uptime)
	
	fmt.Fprintf(w, "# HELP go_goroutines Number of goroutines\n")
	fmt.Fprintf(w, "# TYPE go_goroutines gauge\n")
	fmt.Fprintf(w, "go_goroutines %d\n", runtime.NumGoroutine())
	
	fmt.Fprintf(w, "# HELP memory_usage_bytes Memory usage in bytes\n")
	fmt.Fprintf(w, "# TYPE memory_usage_bytes gauge\n")
	fmt.Fprintf(w, "memory_usage_bytes %d\n", m.Alloc)
}

func healthHandler(w http.ResponseWriter, r *http.Request) {
	health := Health{
		Status:    "healthy",
		Timestamp: time.Now(),
		Uptime:    time.Since(startTime).String(),
		Version:   "2.0.0",
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(health)
}

func envHandler(w http.ResponseWriter, r *http.Request) {
	environment := make(map[string]string)
	for _, item := range os.Environ() {
		splits := strings.SplitN(item, "=", 2)
		if len(splits) == 2 {
			environment[splits[0]] = splits[1]
		}
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(environment)
}

func infoHandler(w http.ResponseWriter, r *http.Request) {
	var m runtime.MemStats
	runtime.ReadMemStats(&m)

	info := map[string]interface{}{
		"version":       "2.0.0",
		"go_version":    runtime.Version(),
		"num_cpu":       runtime.NumCPU(),
		"num_goroutine": runtime.NumGoroutine(),
		"memory": map[string]interface{}{
			"alloc_mb":      float64(m.Alloc) / 1024 / 1024,
			"total_alloc_mb": float64(m.TotalAlloc) / 1024 / 1024,
			"sys_mb":        float64(m.Sys) / 1024 / 1024,
		},
		"uptime":    time.Since(startTime).String(),
		"timestamp": time.Now().Format(time.RFC3339),
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(info)
}

func guestbookGetHandler(w http.ResponseWriter, r *http.Request) {
	guestbookEntriesMutex.RLock()
	defer guestbookEntriesMutex.RUnlock()

	entries := make([]GuestbookEntry, len(guestbookEntries))
	for i, message := range guestbookEntries {
		entries[i] = GuestbookEntry{
			ID:        i + 1,
			Message:   message,
			Timestamp: startTime.Add(time.Duration(i) * time.Minute), // Fake timestamps
		}
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(entries)
}

func guestbookPostHandler(w http.ResponseWriter, r *http.Request) {
	var entry struct {
		Message string `json:"message"`
	}

	if err := json.NewDecoder(r.Body).Decode(&entry); err != nil {
		http.Error(w, "Invalid JSON", http.StatusBadRequest)
		return
	}

	if strings.TrimSpace(entry.Message) == "" {
		http.Error(w, "Message cannot be empty", http.StatusBadRequest)
		return
	}

	guestbookEntriesMutex.Lock()
	guestbookEntries = append(guestbookEntries, entry.Message)
	guestbookEntriesMutex.Unlock()

	log.Printf("GUESTBOOK: New entry added: %s", entry.Message)

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"status": "success"})
}

func main() {
	log.Printf("🚀 Starting Hello World Modern v2.0.0")
	
	// Initialize with some sample data
	guestbookEntries = []string{
		"Welcome to GitOps Demo! 🎉",
		"This app has Prometheus metrics 📊",  
		"Add your own message below! ✨",
	}

	r := mux.NewRouter()

	// Web routes
	r.HandleFunc("/", homeHandler)
	r.HandleFunc("/health", healthHandler)
	r.HandleFunc("/healthz", healthHandler)
	r.HandleFunc("/metrics", metricsHandler)
	r.HandleFunc("/metrics-prometheus", metricsPrometheusHandler)
	r.HandleFunc("/env", envHandler)
	r.HandleFunc("/info", infoHandler)

	// API routes
	r.HandleFunc("/api/guestbook", guestbookGetHandler).Methods("GET")
	r.HandleFunc("/api/guestbook", guestbookPostHandler).Methods("POST")

	// Apply middleware
	handler := metricsMiddleware(r)

	port := os.Getenv("PORT")
	if port == "" {
		port = "3000"
	}

	log.Printf("📡 Server listening on port %s", port)
	log.Printf("🌐 Visit: http://localhost:%s", port)
	log.Fatal(http.ListenAndServe(":"+port, handler))
}