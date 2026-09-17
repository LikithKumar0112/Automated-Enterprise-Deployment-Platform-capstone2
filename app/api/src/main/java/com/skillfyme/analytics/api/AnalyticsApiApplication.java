package com.skillfyme.analytics.api;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

import java.time.Instant;
import java.util.Map;

@SpringBootApplication
public class AnalyticsApiApplication {

    public static void main(String[] args) {
        SpringApplication.run(AnalyticsApiApplication.class, args);
    }

    @RestController
    static class StatusController {
        @GetMapping("/")
        Map<String, Object> status() {
            return Map.of(
                    "service", "analytics-api",
                    "status", "up",
                    "time", Instant.now().toString()
            );
        }
    }
}
