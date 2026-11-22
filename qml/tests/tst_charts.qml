import QtQuick
import QtTest
import ProcessLama

Item {
    width: 400
    height: 300

    Sparkline { id: sparkline }
    HistoryChart { id: chart; width: 300; formatValue: v => Format.percent(v) }

    TestCase {
        name: "Charts"
        when: windowShown

        function test_gaps_lift_the_pen() {
            sparkline.maxValue = 10
            sparkline.samples = [1, 2, NaN, 4, 5]
            compare(sparkline.lines.length, 2)
            compare(sparkline.lines[0].length, 2)
            compare(sparkline.lines[1].length, 2)
        }

        function test_scale_falls_back_to_the_largest_sample() {
            sparkline.maxValue = 0
            sparkline.samples = [1, NaN, 8, 3]
            compare(sparkline.effectiveMax, 8)
            sparkline.samples = [0, 0]
            compare(sparkline.effectiveMax, 0.1)
        }

        function test_history_aligns_right() {
            chart.samples = [1, 2, 3]
            compare(chart.sampleCount, 3)
            compare(chart.leading, 57)
            compare(chart.highlighted, 2)
        }

        function test_bars_touch_on_whole_pixels() {
            chart.samples = [1, 5, 2, 8, 3, 7, 4, 6, 9, 2]
            const bars = findChild(chart, "bars")
            verify(bars)
            for (let i = 0; i < bars.count; ++i) {
                const bar = bars.itemAt(i)
                compare(bar.x0, Math.round(bar.x0))
                if (i + 1 < bars.count)
                    compare(bars.itemAt(i + 1).x0, bar.x1, "gap after bar " + i)
                verify(bar.x1 - bar.x0 >= 1)
            }
        }

        function test_diverging_labels_rates() {
            chart.diverging = true
            chart.samples = [1024]
            chart.lowerSamples = [NaN]
            compare(chart.hoverLabel(0), "1.0 KB/s / –")
            chart.diverging = false
        }
    }
}
