package com.skillfyme.analytics.dataprocessor;

import java.time.Instant;
import java.util.concurrent.ThreadLocalRandom;

/**
 * Stand-in for the hourly analytics-data-processor CronJob body. Logs to
 * stdout so it shows up wherever Fluentd is shipping container logs.
 */
public final class BatchProcessor {

    public static void main(String[] args) throws InterruptedException {
        long start = System.currentTimeMillis();
        System.out.printf("[%s] analytics-data-processor: batch triggered%n", Instant.now());

        // Simulated work - a real implementation would pull from the
        // analytics product's data source here.
        Thread.sleep(1500);
        int recordsProcessed = ThreadLocalRandom.current().nextInt(40_000, 55_000);

        double elapsedSeconds = (System.currentTimeMillis() - start) / 1000.0;
        System.out.printf("[%s] analytics-data-processor: batch complete - %,d records processed in %.1fs%n",
                Instant.now(), recordsProcessed, elapsedSeconds);
    }
}
