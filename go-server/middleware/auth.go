package middleware

import (
	"net/http"
	"strings"
)

// AuthMiddleware checks for valid authentication token
func AuthMiddleware(authToken string) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			// Check Authorization header
			auth := r.Header.Get("Authorization")
			if auth != "" {
				// Support "Bearer <token>" format
				if strings.HasPrefix(auth, "Bearer ") {
					token := strings.TrimPrefix(auth, "Bearer ")
					if token == authToken {
						next.ServeHTTP(w, r)
						return
					}
				}
				// Support direct token
				if auth == authToken {
					next.ServeHTTP(w, r)
					return
				}
			}

			// Check query parameter (for WebSocket)
			if token := r.URL.Query().Get("token"); token != "" {
				if token == authToken {
					next.ServeHTTP(w, r)
					return
				}
			}

			// Unauthorized
			http.Error(w, "Unauthorized", http.StatusUnauthorized)
		})
	}
}
