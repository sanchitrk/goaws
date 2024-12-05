package main

import (
	"fmt"
	"net/http"
)

func main() {
	fmt.Println("server up and running...")
	http.HandleFunc("/", HelloServer)
	http.ListenAndServe(":8080", nil)
}

func HelloServer(w http.ResponseWriter, r *http.Request) {
	fmt.Println("got request...")
	fmt.Fprintf(w, "Hello, Go AWS Deployed App!")
}
