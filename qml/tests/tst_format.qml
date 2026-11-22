import QtQuick
import QtTest
import ProcessLama

// The display formats mirror the Rust presentation crate and Flutter.
TestCase {
    name: "Format"

    function test_bytes() {
        compare(Format.bytes(0), "0 B")
        compare(Format.bytes(512), "512 B")
        compare(Format.bytes(1536), "1.5 KB")
        compare(Format.bytes(3 * 1024 * 1024 * 1024), "3.0 GB")
    }

    function test_rates_round_to_whole_bytes() {
        compare(Format.rate(1023.6), "1.0 KB/s")
        compare(Format.rate(0), "0 B/s")
    }

    function test_percent() {
        compare(Format.percent(0), "0.0%")
        compare(Format.percent(-3), "0.0%")
        compare(Format.percent(3.14), "3.1%")
        compare(Format.percent(42.6), "43%")
    }

    function test_ports() {
        compare(Format.ports(null), "-")
        compare(Format.ports({ listening: [8080, 5432], other: [1, 2, 3] }), "8080, 5432 +3")
        compare(Format.ports({ listening: [], other: [9] }), "+1")
    }

    function test_remote_bytes() {
        compare(Format.remoteBytes(512), "512 B")
        compare(Format.remoteBytes(1536), "1.5 KB")
        compare(Format.remoteBytes(64 * 1024 * 1024), "64 MB")
    }

    function test_duration() {
        L10n.language = "en"
        compare(Format.duration(42000), "42 s")
        compare(Format.duration(5 * 60000), "5 min")
        compare(Format.duration(125 * 60000), "2 h 5 min")
    }

    function test_toast_failures_translate() {
        L10n.language = "en"
        const text = Labels.toast("remoteHostConnectFailed", ["box", "@failure:heartbeatLost"])
        verify(text.indexOf("box") >= 0)
        verify(text.indexOf("@failure") < 0)
        compare(Labels.failure("noSuchCode"), L10n.t("remoteFailureInternal"))
    }

    function test_german_catalog() {
        L10n.language = "de"
        verify(L10n.t("preferences") !== "preferences")
        verify(L10n.t("processCount", [3]).indexOf("3") >= 0)
        L10n.language = "en"
    }
}
