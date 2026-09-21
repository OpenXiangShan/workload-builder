// Firefox profile preferences for the speedometer workload.
//
// The guest derives its clock from retired instructions and believes it is a
// roughly 128 MIPS machine, so a benchmark run that takes a minute on real
// hardware appears to take hours. Every default that reacts to elapsed time
// must therefore be neutralised, or the browser aborts the run long before it
// finishes. The remaining settings remove network access, which the guest does
// not have, and first-run behaviour, which would otherwise dominate startup.

// Nothing may be declared hung, however long it takes.
user_pref("dom.max_script_run_time", 0);
user_pref("dom.max_chrome_script_run_time", 0);
user_pref("dom.max_ext_script_run_time", 0);
user_pref("dom.ipc.processHangMonitor", false);
user_pref("browser.sessionstore.resume_from_crash", false);

// Timers must not be throttled or budgeted; the benchmark drives itself
// through setTimeout and rAF and a throttled queue changes what is measured.
user_pref("dom.min_background_timeout_value", 0);
user_pref("dom.timeout.throttling_delay", 0);
user_pref("dom.timeout.enable_budget_timer_throttling", false);
user_pref("dom.timeout.background_throttling_max_budget", -1);
user_pref("dom.suspend_inactive_grandchild", false);

// The projected score assumes every measured interval is compute-bound. A
// vsync-paced refresh driver would instead quantise async time to a fixed
// wall-clock interval that does not scale with the target core's throughput.
// Zero selects the driver's unthrottled rate.
user_pref("layout.frame_rate", 0);

// Report real durations rather than the privacy-rounded ones.
user_pref("privacy.reduceTimerPrecision", false);
user_pref("privacy.resistFingerprinting", false);

// Software rendering only; there is no GPU behind the emulator.
user_pref("gfx.webrender.software", true);

// Sandboxing needs kernel features and a filesystem layout the guest does not
// provide, and contributes nothing to what is being measured.
user_pref("security.sandbox.content.level", 0);

// No network exists beyond loopback. Anything that reaches out stalls on a
// connection that will never complete.
user_pref("network.dns.disablePrefetch", true);
user_pref("network.prefetch-next", false);
user_pref("network.http.speculative-parallel-limit", 0);
user_pref("browser.urlbar.speculativeConnect.enabled", false);
user_pref("network.captive-portal-service.enabled", false);
user_pref("network.connectivity-service.enabled", false);
user_pref("browser.safebrowsing.malware.enabled", false);
user_pref("browser.safebrowsing.phishing.enabled", false);
user_pref("browser.safebrowsing.downloads.enabled", false);
user_pref("browser.safebrowsing.blockedURIs.enabled", false);
user_pref("browser.search.update", false);
user_pref("app.update.enabled", false);
user_pref("app.update.auto", false);
user_pref("extensions.update.enabled", false);
user_pref("extensions.update.autoUpdateDefault", false);
user_pref("extensions.blocklist.enabled", false);
user_pref("extensions.systemAddon.update.enabled", false);
user_pref("datareporting.healthreport.uploadEnabled", false);
user_pref("datareporting.policy.dataSubmissionEnabled", false);
user_pref("toolkit.telemetry.enabled", false);
user_pref("toolkit.telemetry.unified", false);
user_pref("toolkit.telemetry.archive.enabled", false);
user_pref("browser.ping-centre.telemetry", false);
user_pref("browser.discovery.enabled", false);
user_pref("browser.region.network.url", "");
user_pref("browser.region.update.enabled", false);

// First-run and new-tab machinery adds startup work and network requests
// without contributing anything to the benchmark.
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("browser.startup.homepage", "about:blank");
user_pref("browser.newtabpage.enabled", false);
user_pref("browser.aboutwelcome.enabled", false);
user_pref("browser.startup.firstrunSkipsHomepage", true);
user_pref("datareporting.policy.firstRunURL", "");
user_pref("toolkit.startup.max_resumed_crashes", -1);
user_pref("browser.tabs.crashReporting.sendReport", false);

// The rootfs lives in RAM, so a disk cache only duplicates pages already
// resident and adds noise to the profile.
user_pref("browser.cache.disk.enable", false);
user_pref("browser.cache.memory.enable", true);
