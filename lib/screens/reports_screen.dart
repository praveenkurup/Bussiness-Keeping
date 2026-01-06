import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:table_calendar/table_calendar.dart';
import 'reports_detail_screen.dart';
import '../firestore_service.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => ReportsScreenState();
}

class ReportsScreenState extends State<ReportsScreen>
    with AutomaticKeepAliveClientMixin {
  DateTime? startDate;
  DateTime? endDate;
  DateTime _focusedDayStart = DateTime.now();
  DateTime _focusedDayEnd = DateTime.now();
  bool _isLoading = true;
  bool _hasConfig = false;
  Set<String> _datesWithData = {};
  int _refreshKey = 0; // Key to force calendar rebuild
  DateTime? _lastRefreshTime;

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
        print('=== REPORTS CALENDAR REFRESH ===');
        print('Dates with data loaded: $datesWithData');
        print('Total dates: ${datesWithData.length}');
        print('================================');
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
    // Only refresh when screen comes into view and we haven't refreshed recently
    if (!_isLoading) {
      _debouncedRefresh();
    }
  }

  @override
  void didUpdateWidget(ReportsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only refresh when actually needed (e.g., when returning from detail screen)
    // Don't refresh on every widget update to avoid constant refreshing
  }

  // Debounced refresh method to prevent constant refreshing
  void _debouncedRefresh() {
    final now = DateTime.now();
    if (_lastRefreshTime != null &&
        now.difference(_lastRefreshTime!).inSeconds < 3) {
      print('Reports Screen: Skipping refresh - too soon (debounced)');
      return;
    }

    _lastRefreshTime = now;
    print('Reports Screen: Debounced refresh triggered');
    if (mounted) {
      _checkUserConfig();
    }
  }

  // Add a method to manually refresh when needed
  void refreshCalendarData() {
    _debouncedRefresh();
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
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE0E0E0)),
                      ),
                      child: Text(
                        'Reports',
                        style: GoogleFonts.quicksand(
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                          color: Colors.black,
                          height: 1.25,
                        ),
                      ),
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
                    else
                      _buildReportsContent(size),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildReportsContent(Size size) {
    final DateTime now = DateTime.now();
    final DateTime first = DateTime(now.year - 2);
    final DateTime last = DateTime(now.year + 2);

    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Date range selection container
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE0E0E0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Select date range',
                  style: GoogleFonts.quicksand(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.black,
                    height: 1.25,
                  ),
                ),
                if (startDate != null || endDate != null) ...[
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'From:',
                            style: GoogleFonts.quicksand(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: Colors.grey[600],
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            startDate != null
                                ? '${startDate!.day}/${startDate!.month}/${startDate!.year}'
                                : 'Not selected',
                            style: GoogleFonts.quicksand(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.black,
                            ),
                          ),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            'To:',
                            style: GoogleFonts.quicksand(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: Colors.grey[600],
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            endDate != null
                                ? '${endDate!.day}/${endDate!.month}/${endDate!.year}'
                                : 'Not selected',
                            style: GoogleFonts.quicksand(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.black,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Calendars section
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  // Start Date Calendar
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE0E0E0)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Start Date',
                          style: GoogleFonts.quicksand(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: Colors.black,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 420),
                            child: TableCalendar(
                              key: ValueKey(
                                'start_date_$_refreshKey',
                              ), // Force rebuild when data changes
                              firstDay: first,
                              lastDay: last,
                              focusedDay: _focusedDayStart,
                              selectedDayPredicate: (day) {
                                return isSameDay(startDate, day);
                              },
                              onDaySelected: (selectedDay, focusedDay) {
                                setState(() {
                                  startDate = selectedDay;
                                  _focusedDayStart = focusedDay;
                                });
                              },
                              onPageChanged: (focusedDay) {
                                _focusedDayStart = focusedDay;
                              },
                              calendarStyle: CalendarStyle(
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
                                selectedDecoration: const BoxDecoration(
                                  color: Color(0xFF6A5AE0),
                                  shape: BoxShape.circle,
                                ),
                                selectedTextStyle: GoogleFonts.quicksand(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                                defaultTextStyle: GoogleFonts.quicksand(
                                  color: Colors.black,
                                  fontWeight: FontWeight.w500,
                                ),
                                weekendTextStyle: GoogleFonts.quicksand(
                                  color: Colors.red[700],
                                  fontWeight: FontWeight.w500,
                                ),
                                outsideTextStyle: GoogleFonts.quicksand(
                                  color: Colors.grey[400],
                                  fontWeight: FontWeight.w400,
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
                                defaultBuilder: (context, day, focusedDay) {
                                  final dateString =
                                      '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
                                  final hasData = _datesWithData.contains(
                                    dateString,
                                  );

                                  // Debug: Print when checking a date
                                  if (hasData) {
                                    print(
                                      'Reports Calendar: Date $dateString has data (highlighted)',
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
                                              color: const Color(0xFF29C7AC),
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
                                outsideBuilder: (context, day, focusedDay) {
                                  final dateString =
                                      '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
                                  final hasData = _datesWithData.contains(
                                    dateString,
                                  );

                                  // Debug: Print when checking a date
                                  if (hasData) {
                                    print(
                                      'Reports Calendar: Date $dateString has data (highlighted)',
                                    );
                                  }

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
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  // End Date Calendar
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE0E0E0)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'End Date',
                          style: GoogleFonts.quicksand(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: Colors.black,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 420),
                            child: TableCalendar(
                              key: ValueKey(
                                'end_date_$_refreshKey',
                              ), // Force rebuild when data changes
                              firstDay: first,
                              lastDay: last,
                              focusedDay: _focusedDayEnd,
                              selectedDayPredicate: (day) {
                                return isSameDay(endDate, day);
                              },
                              onDaySelected: (selectedDay, focusedDay) {
                                setState(() {
                                  endDate = selectedDay;
                                  _focusedDayEnd = focusedDay;
                                });
                              },
                              onPageChanged: (focusedDay) {
                                setState(() {
                                  _focusedDayEnd = focusedDay;
                                });
                              },
                              calendarStyle: CalendarStyle(
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
                                selectedDecoration: const BoxDecoration(
                                  color: Color(0xFF6A5AE0),
                                  shape: BoxShape.circle,
                                ),
                                selectedTextStyle: GoogleFonts.quicksand(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                                defaultTextStyle: GoogleFonts.quicksand(
                                  color: Colors.black,
                                  fontWeight: FontWeight.w500,
                                ),
                                weekendTextStyle: GoogleFonts.quicksand(
                                  color: Colors.red[700],
                                  fontWeight: FontWeight.w500,
                                ),
                                outsideTextStyle: GoogleFonts.quicksand(
                                  color: Colors.grey[400],
                                  fontWeight: FontWeight.w400,
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
                                defaultBuilder: (context, day, focusedDay) {
                                  final dateString =
                                      '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
                                  final hasData = _datesWithData.contains(
                                    dateString,
                                  );

                                  // Debug: Print when checking a date
                                  if (hasData) {
                                    print(
                                      'Reports Calendar: Date $dateString has data (highlighted)',
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
                                              color: const Color(0xFF29C7AC),
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
                                outsideBuilder: (context, day, focusedDay) {
                                  final dateString =
                                      '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
                                  final hasData = _datesWithData.contains(
                                    dateString,
                                  );

                                  // Debug: Print when checking a date
                                  if (hasData) {
                                    print(
                                      'Reports Calendar: Date $dateString has data (highlighted)',
                                    );
                                  }

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
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Generate Report Button
                  if (startDate != null && endDate != null)
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          // Validate date range before navigating
                          if (endDate!.isBefore(startDate!)) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Invalid date range: End date cannot be before start date. Please select a valid date range.',
                                  style: GoogleFonts.quicksand(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                backgroundColor: Colors.red[600],
                                duration: const Duration(seconds: 4),
                                behavior: SnackBarBehavior.floating,
                                margin: const EdgeInsets.all(16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            );
                            return;
                          }

                          // Check if dates are too far in the future
                          final now = DateTime.now();
                          if (startDate!.isAfter(now) ||
                              endDate!.isAfter(now)) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Invalid date range: Cannot select future dates. Please select dates from today or earlier.',
                                  style: GoogleFonts.quicksand(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                backgroundColor: Colors.red[600],
                                duration: const Duration(seconds: 4),
                                behavior: SnackBarBehavior.floating,
                                margin: const EdgeInsets.all(16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            );
                            return;
                          }

                          // Check if date range is too large (more than 2 years)
                          final daysDifference = endDate!
                              .difference(startDate!)
                              .inDays;
                          if (daysDifference > 730) {
                            // 2 years = 730 days
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Date range too large: Please select a date range within 2 years for better performance.',
                                  style: GoogleFonts.quicksand(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                backgroundColor: Colors.orange[600],
                                duration: const Duration(seconds: 4),
                                behavior: SnackBarBehavior.floating,
                                margin: const EdgeInsets.all(16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            );
                            return;
                          }

                          Navigator.of(context)
                              .push(
                                MaterialPageRoute(
                                  builder: (_) => ReportsDetailScreen(
                                    startDate: startDate!,
                                    endDate: endDate!,
                                  ),
                                ),
                              )
                              .then((result) {
                                // Always refresh calendar data when returning from reports detail screen
                                // since users might have created/edited/deleted reports from daily reports
                                print(
                                  'Reports Screen: Returning from detail screen - refreshing',
                                );
                                Future.delayed(
                                  const Duration(milliseconds: 500),
                                  () {
                                    if (mounted) {
                                      _debouncedRefresh();
                                    }
                                  },
                                );
                              });
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF6A5AE0),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          'Generate Report',
                          style: GoogleFonts.quicksand(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
