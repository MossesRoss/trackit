import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

class SexyProgressChart extends StatelessWidget {
  final bool isDark;
  const SexyProgressChart({super.key, this.isDark = false});

  @override
  Widget build(BuildContext context) {
    // Colors based on theme/mode
    final Color mainColor = isDark ? Colors.cyanAccent : Colors.blueAccent;
    final Color belowColor = mainColor.withAlpha(26);
    final Color gridColor = isDark ? Colors.white10 : Colors.black12;

    return AspectRatio(
      aspectRatio: 1.70,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.all(Radius.circular(18)),
          color: isDark ? const Color(0xff232d37) : Colors.white,
          boxShadow: [
            if (!isDark)
              BoxShadow(
                color: Colors.grey.withAlpha(26),
                spreadRadius: 5,
                blurRadius: 7,
                offset: const Offset(0, 3),
              ),
          ],
        ),
        child: Padding(
          padding:
              const EdgeInsets.only(right: 18, left: 12, top: 24, bottom: 12),
          child: LineChart(
            mainData(mainColor, belowColor, gridColor),
          ),
        ),
      ),
    );
  }

  LineChartData mainData(Color mainColor, Color belowColor, Color gridColor) {
    return LineChartData(
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        horizontalInterval: 1,
        getDrawingHorizontalLine: (value) => FlLine(
          color: gridColor,
          strokeWidth: 1,
        ),
      ),
      titlesData: FlTitlesData(
        show: true,
        rightTitles:
            const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 30,
            interval: 1,
            getTitlesWidget: bottomTitleWidgets,
          ),
        ),
        leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      ),
      borderData: FlBorderData(show: false),
      minX: 0,
      maxX: 6,
      minY: 0,
      maxY: 6,
      lineBarsData: [
        LineChartBarData(
          // REALITY CHECK: Connection to real DB would happen here.
          // For now, we define the visual structure.
          spots: const [
            FlSpot(0, 2),
            FlSpot(1, 1.5),
            FlSpot(2, 3),
            FlSpot(3, 2.8),
            FlSpot(4, 4),
            FlSpot(5, 3.8),
            FlSpot(6, 5),
          ],
          isCurved: true,
          gradient:
              LinearGradient(colors: [mainColor.withAlpha(204), mainColor]),
          barWidth: 5,
          isStrokeCapRound: true,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(
            show: true,
            gradient: LinearGradient(
              colors: [mainColor.withAlpha(77), belowColor],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
        ),
      ],
    );
  }

  Widget bottomTitleWidgets(double value, TitleMeta meta) {
    const style = TextStyle(
        fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey);
    Widget text;
    switch (value.toInt()) {
      case 0:
        text = const Text('Mon', style: style);
        break;
      case 2:
        text = const Text('Wed', style: style);
        break;
      case 4:
        text = const Text('Fri', style: style);
        break;
      case 6:
        text = const Text('Sun', style: style);
        break;
      default:
        text = const Text('', style: style);
        break;
    }
    return SideTitleWidget(axisSide: meta.axisSide, child: text);
  }
}
