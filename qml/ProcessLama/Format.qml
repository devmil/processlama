pragma Singleton
import QtQuick

// The display formats of the explorer; they mirror processlama-presentation.
QtObject {
    readonly property var _units: ["B", "KB", "MB", "GB", "TB"]

    function bytes(value) {
        let amount = Number(value)
        if (!(amount > 0))
            return "0 B"
        let unit = 0
        while (amount >= 1024 && unit < _units.length - 1) {
            amount /= 1024
            ++unit
        }
        return amount.toFixed(unit === 0 ? 0 : 1) + " " + _units[unit]
    }

    function rate(bytesPerSecond) {
        return bytes(Math.round(Number(bytesPerSecond) || 0)) + "/s"
    }

    function percent(value) {
        const amount = Number(value) || 0
        if (amount <= 0)
            return "0.0%"
        return amount.toFixed(amount >= 10 ? 0 : 1) + "%"
    }

    function _pad(value, width) {
        return String(value).padStart(width, "0")
    }

    /// `HH:mm:ss` local time of a Unix millisecond timestamp.
    function clock(unixMs) {
        if (!(unixMs > 0))
            return L10n.t("unknown")
        const date = new Date(unixMs)
        return _pad(date.getHours(), 2) + ":" + _pad(date.getMinutes(), 2) + ":" + _pad(date.getSeconds(), 2)
    }

    /// A short duration: seconds, minutes, or hours and minutes.
    function duration(milliseconds) {
        const seconds = Math.max(0, Math.floor(milliseconds / 1000))
        if (seconds < 60)
            return L10n.t("remoteDurationSeconds", [seconds])
        const minutes = Math.floor(seconds / 60)
        if (minutes < 60)
            return L10n.t("remoteDurationMinutes", [minutes])
        return L10n.t("remoteDurationHours", [Math.floor(minutes / 60), minutes % 60])
    }

    /// `512 KB`-style sizes in binary units (remote hosts and helpers).
    function remoteBytes(value) {
        const units = ["B", "KB", "MB", "GB"]
        let amount = Number(value) || 0
        let unit = 0
        while (amount >= 1024 && unit < units.length - 1) {
            amount /= 1024
            ++unit
        }
        return amount.toFixed(unit === 0 || amount >= 10 ? 0 : 1) + " " + units[unit]
    }

    /// Listening ports, then how many other local ports: `8080, 5432 +12`.
    function ports(value) {
        if (!value)
            return "-"
        const parts = []
        if (value.listening.length > 0)
            parts.push(value.listening.join(", "))
        if (value.other.length > 0)
            parts.push("+" + value.other.length)
        return parts.join(" ")
    }
}
