import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:table_calendar/table_calendar.dart';
import 'daily_report_detail_screen.dart';
import '../firestore_service.dart';

class DailyReportsScreen extends StatefulWidget {
  const DailyReportsScreen({super.key});

  @override
  State<DailyReportsScreen> createState() => DailyReportsScreenState();
}

class DailyReportsScreenState extends State<DailyReportsScreen>
    with AutomaticKeepAliveClientMixin {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  bool _isLoading = true;
  bool _hasConfig = false;
  Set<String> _datesWithData = {};
  int _refreshKey = 0; // Key to force calendar rebuild

  @override
  bool get wantKeepAlive => false; // Don't keep alive to allow refresh

  @override
  void initState() {
    super.initState();
    _checkUserConfig();
  }

  Future<void> _checkUserConfig() async {
    setState(() {
      _isLoading = true;
    });

    final config = await FirestoreService.getUserConfig();
    Set<String> datesWithData = {};

    if (config != null) {
      // Load dates_with_data from total_report
      final totalReport = await FirestoreService.getTotalReport();
      if (totalReport != null && totalReport['dates_with_data'] != null) {
        final List<dynamic> dates =
            totalReport['dates_with_data'] as List<dynamic>;
        datesWithData = dates.map((date) => date.toString()).toSet();

        // Debug: Print the dates with data
        print('=== CALENDAR REFRESH ===');
        print('Dates with data loaded: $datesWithData');
        print('Total dates: ${datesWithData.length}');
        print('========================');
      }
    }

    if (mounted) {
      setState(() {
        _hasConfig = config != null;
        _datesWithData = datesWithData;
        _isLoading = false;
        _refreshKey++; // Force calendar rebuild
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Refresh config when screen comes into view
    _checkUserConfig();
  }

  @override
  void didUpdateWidget(DailyReportsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Refresh when widget updates (e.g., when returning from edit screen)
    _checkUserConfig();
  }

  // Add a method to manually refresh when needed
  void refreshCalendarData() {
    print('Daily Reports Screen: Manual refresh triggered');
    if (mounted) {
      _checkUserConfig();
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    final Size size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Padding(
                padding: EdgeInsets.symmetric(horizontal: size.width * 0.06),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(height: size.height * 0.025),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Daily Reports',
                            style: GoogleFonts.quicksand(
                              fontSize: 26,
                              fontWeight: FontWeight.w700,
                              color: Colors.black,
                              height: 1.25,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (!_hasConfig)
                      Expanded(
                        child: Center(
                          child: Container(
                            margin: const EdgeInsets.symmetric(vertical: 40),
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: Colors.grey[50],
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: Colors.grey[300]!,
                                width: 1,
                              ),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.settings_outlined,
                                  size: 48,
                                  color: Colors.grey[600],
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'Please configure your business by going to settings',
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.quicksand(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.black87,
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      )
                    else ...[
                      Text(
                        'Select a date',
                        style: GoogleFonts.quicksand(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Colors.black,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 150),
                      Expanded(
                        child: SingleChildScrollView(
                          child: Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 420),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: const Color(0xFFE0E0E0),
                                  ),
                                ),
                                padding: const EdgeInsets.all(8),
                                child: TableCalendar(
                                  key: ValueKey(
                                    _refreshKey,
                                  ), // Force rebuild when data changes
                                  firstDay: DateTime(DateTime.now().year - 2),
                                  lastDay: DateTime(DateTime.now().year + 2),
                                  focusedDay: _focusedDay,
                                  selectedDayPredicate: (day) {
                                    return isSameDay(_selectedDay, day);
                                  },
                                  onDaySelected: (selectedDay, focusedDay) {
                                    setState(() {
                                      _selectedDay = selectedDay;
                                      _focusedDay = focusedDay;
                                    });
                                    Navigator.of(context)
                                        .push(
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                DailyReportDetailScreen(
                                                  date: selectedDay,
                                                ),
                                          ),
                                        )
                                        .then((result) {
                                          // Refresh calendar data when returning from detail screen
                                          // especially if a report was created/edited/deleted
                                          if (result == true) {
                                            // Add a small delay to ensure Firestore has updated
                                            Future.delayed(
                                              const Duration(milliseconds: 500),
                                              () {
                                                if (mounted) {
                                                  _checkUserConfig();
                                                }
                                              },
                                            );
                                          }
                                        });
                                  },
                                  onPageChanged: (focusedDay) {
                                    _focusedDay = focusedDay;
                                  },
                                  calendarStyle: CalendarStyle(
                                    // Today's date style
                                    todayDecoration: BoxDecoration(
                                      color: const Color(
                                        0xFF6A5AE0,
                                      ).withOpacity(0.3),
                                      shape: BoxShape.circle,
                                    ),
                                    todayTextStyle: GoogleFonts.quicksand(
                                      color: Colors.black,
                                      fontWeight: FontWeight.w700,
                                    ),
                                    // Selected date style
                                    selectedDecoration: const BoxDecoration(
                                      color: Color(0xFF6A5AE0),
                                      shape: BoxShape.circle,
                                    ),
                                    selectedTextStyle: GoogleFonts.quicksand(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                    ),
                                    // Default day style
                                    defaultTextStyle: GoogleFonts.quicksand(
                                      color: Colors.black,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    // Weekend style
                                    weekendTextStyle: GoogleFonts.quicksand(
                                      color: Colors.red[700],
                                      fontWeight: FontWeight.w500,
                                    ),
                                    // Outside month style
                                    outsideTextStyle: GoogleFonts.quicksand(
                                      color: Colors.grey[400],
                                      fontWeight: FontWeight.w400,
                                    ),
                                    // Marker for dates with data
                                    markerDecoration: const BoxDecoration(
                                      color: Color(0xFF29C7AC),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  headerStyle: HeaderStyle(
                                    formatButtonVisible: false,
                                    titleCentered: true,
                                    titleTextStyle: GoogleFonts.quicksand(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.black,
                                    ),
                                    leftChevronIcon: const Icon(
                                      Icons.chevron_left,
                                      color: Colors.black,
                                    ),
                                    rightChevronIcon: const Icon(
                                      Icons.chevron_right,
                                      color: Colors.black,
                                    ),
                                  ),
                                  daysOfWeekStyle: DaysOfWeekStyle(
                                    weekdayStyle: GoogleFonts.quicksand(
                                      fontWeight: FontWeight.w600,
                                      color: Colors.black87,
                                    ),
                                    weekendStyle: GoogleFonts.quicksand(
                                      fontWeight: FontWeight.w600,
                                      color: Colors.red[700],
                                    ),
                                  ),
                                  calendarBuilders: CalendarBuilders(
                                    // Custom builder for days with data
                                    defaultBuilder: (context, day, focusedDay) {
                                      final dateString =
                                          '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
                                      final hasData = _datesWithData.contains(
                                        dateString,
                                      );

                                      // Debug: Print when checking a date
                                      if (hasData) {
                                        print(
                                          'Calendar: Date $dateString has data (highlighted)',
                                        );
                                      }

                                      return Container(
                                        margin: const EdgeInsets.all(4),
                                        decoration: BoxDecoration(
                                          color: hasData
                                              ? const Color(
                                                  0xFF29C7AC,
                                                ).withOpacity(0.2)
                                              : null,
                                          shape: BoxShape.circle,
                                          border: hasData
                                              ? Border.all(
                                                  color: const Color(
                                                    0xFF29C7AC,
                                                  ),
                                                  width: 2,
                                                )
                                              : null,
                                        ),
                                        child: Center(
                                          child: Text(
                                            '${day.day}',
                                            style: GoogleFonts.quicksand(
                                              color: Colors.black,
                                              fontWeight: hasData
                                                  ? FontWeight.w700
                                                  : FontWeight.w500,
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                    // Custom builder for outside days with data
                                    outsideBuilder: (context, day, focusedDay) {
                                      final dateString =
                                          '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
                                      final hasData = _datesWithData.contains(
                                        dateString,
                                      );

                                      if (!hasData) return null;

                                      return Container(
                                        margin: const EdgeInsets.all(4),
                                        decoration: BoxDecoration(
                                          color: const Color(
                                            0xFF29C7AC,
                                          ).withOpacity(0.1),
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: const Color(
                                              0xFF29C7AC,
                                            ).withOpacity(0.5),
                                            width: 1,
                                          ),
                                        ),
                                        child: Center(
                                          child: Text(
                                            '${day.day}',
                                            style: GoogleFonts.quicksand(
                                              color: Colors.grey[400],
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
      ),
    );
  }
}
