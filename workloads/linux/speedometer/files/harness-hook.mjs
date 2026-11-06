/*
 * Couples the Speedometer harness to the NEMU control endpoints.
 *
 * This is loaded after resources/main.mjs, which publishes the benchmark client
 * on globalThis. Wrapping that client's lifecycle callbacks is the smallest
 * change that yields a precise profiled region: nothing in the harness or the
 * suites is modified.
 *
 * Requests are synchronous on purpose. The profiler must be armed before the
 * first iteration executes any measured work, and the run must not end before
 * the results have been handed to the server.
 */

const CONTROL_ROI_START = "/control/roi-start";
const CONTROL_RESULTS = "/control/results";
const CONTROL_FINISH = "/control/finish";
const CONTROL_ABORT = "/control/abort";

function call(path, body) {
    try {
        const request = new XMLHttpRequest();
        request.open(body === undefined ? "GET" : "POST", path, false);
        request.send(body);
    } catch (error) {
        console.error(`speedometer control request to ${path} failed`, error);
    }
}

/* Each field is guarded separately: a run that produced partial results is
 * still worth reporting, and losing all of them to one serialization failure
 * would waste the whole run. */
function attempt(what, produce) {
    try {
        return produce();
    } catch (error) {
        console.error(`speedometer ${what} failed`, error);
        return null;
    }
}

function collectResults(client, complete) {
    const computed = attempt("score computation",
        () => client._computeResults(client._measuredValuesList, "score"));

    const results = {
        benchmark: "Speedometer 3.1",
        iterationCount: client._measuredValuesList?.length ?? null,
        score: computed?.mean ?? null,
        formattedScore: computed?.formattedMeanAndDelta ?? null,
        isValid: computed?.isValid ?? false,
        metrics: attempt("metrics serialization",
            () => JSON.parse(client._formattedJSONResult({ modern: true }))),
        measuredValues: attempt("measured values serialization",
            () => JSON.parse(client._formattedJSONResult({ modern: false }))),
    };

    if (!complete)
        results.incomplete = true;

    return results;
}

function install(client) {
    const willStartFirstIteration = client.willStartFirstIteration.bind(client);
    const didFinishLastIteration = client.didFinishLastIteration.bind(client);
    const handleError = client.handleError.bind(client);

    client.willStartFirstIteration = function (...args) {
        const result = willStartFirstIteration(...args);
        call(CONTROL_ROI_START);
        return result;
    };

    client.didFinishLastIteration = function (metrics) {
        let result;
        try {
            result = didFinishLastIteration(metrics);
        } finally {
            call(CONTROL_RESULTS, JSON.stringify(collectResults(client, true)));
            call(CONTROL_FINISH);
        }
        return result;
    };

    client.handleError = function (error) {
        console.error("speedometer run failed", error);
        try {
            return handleError(error);
        } finally {
            call(CONTROL_RESULTS, JSON.stringify(collectResults(client, false)));
            call(CONTROL_ABORT);
        }
    };
}

/* A modal dialog in a headless browser stalls the run with no way out, so route
 * anything that would open one to the abort endpoint instead. */
window.alert = function (message) {
    console.error("speedometer alert", message);
    call(CONTROL_ABORT);
};

if (globalThis.benchmarkClient)
    install(globalThis.benchmarkClient);
else
    console.error("speedometer benchmark client missing; control endpoints not installed");
