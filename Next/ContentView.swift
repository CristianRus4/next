//
//  ContentView.swift
//  Next
//
//  Created by Cristian Rus on 5/11/24.
//

import SwiftUI
import EventKit
import UserNotifications

struct IdentifiableCalendar: Identifiable {
    let id: String
    let calendar: EKCalendar
    
    init(calendar: EKCalendar) {
        self.id = calendar.calendarIdentifier
        self.calendar = calendar
    }
}

struct AgendaView: View {
    let eventStore = EKEventStore()
    @State private var reminders: [EKReminder] = []
    @State private var events: [EKEvent] = []
    @State private var selectedDate = Date()
    @AppStorage("hiddenCalendars") private var hiddenCalendars = Data()
    @AppStorage("hiddenLists") private var hiddenLists = Data()
    @State private var showingComposer = false
    @State private var temperature: Double?
    @State private var weatherDescription: String?
    private let weatherService = WeatherService()
    @State private var weekOffset = 0
    @GestureState private var dragOffset: CGFloat = 0
    @State private var isEventsExpanded = true
    @State private var isRemindersExpanded = true
    
    private var hiddenCalendarIds: Set<String> {
        if let decoded = try? JSONDecoder().decode(Set<String>.self, from: hiddenCalendars) {
            return decoded
        }
        return []
    }
    
    private var hiddenListIds: Set<String> {
        if let decoded = try? JSONDecoder().decode(Set<String>.self, from: hiddenLists) {
            return decoded
        }
        return []
    }
    
    private var navigationTitle: String {
        if Calendar.current.isDateInToday(selectedDate) {
            return "Today"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE" // Full day name
            return formatter.string(from: selectedDate)
        }
    }
    
    private var mondayOfDisplayedWeek: Date {
        let calendar = Calendar.current
        let today = Date()
        
        // Get the weekday component (1 is Sunday, 2 is Monday, etc.)
        let weekday = calendar.component(.weekday, from: today)
        
        // Calculate how many days we need to subtract to get to Monday
        let daysToSubtract = weekday == 1 ? 6 : weekday - 2
        
        // Get Monday by subtracting the calculated days
        let thisMonday = calendar.date(byAdding: .day, value: -daysToSubtract, to: today) ?? today
        
        // Add weeks based on offset
        return calendar.date(byAdding: .weekOfYear, value: weekOffset, to: thisMonday) ?? today
    }
    
    var prefetchedEvents: [EKEvent]
    var prefetchedReminders: [EKReminder]
    
    // Add this computed property inside AgendaView:

    private var preloadedLists: [EKCalendar] {
        eventStore.calendars(for: .reminder)
            .filter { !hiddenListIds.contains($0.calendarIdentifier) }
            .sorted { $0.title < $1.title }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.customBackground
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Day picker with gesture
                    HStack(spacing: 0) {
                        ForEach(0..<7, id: \.self) { index in
                            let date = mondayOfDisplayedWeek.addingTimeInterval(TimeInterval(index * 24 * 60 * 60))
                            DayButton(date: date, isSelected: Calendar.current.isDate(date, inSameDayAs: selectedDate)) {
                                HapticManager.selection()
                                selectedDate = date
                                Task {
                                    if Calendar.current.isDateInToday(date) {
                                        await fetchWeather()
                                    }
                                    await fetchEvents(for: date)
                                    await fetchReminders(for: date)
                                }
                            }
                        }
                    }
                    .contentShape(Rectangle())  // Add this line to make the entire HStack tappable
                    .gesture(
                        DragGesture()
                            .updating($dragOffset) { value, state, _ in
                                state = value.translation.width
                            }
                            .onEnded { value in
                                let threshold: CGFloat = 8  // Changed from 15 to 8
                                if value.translation.width > threshold {
                                    weekOffset -= 1
                                    HapticManager.selection()
                                } else if value.translation.width < -threshold {
                                    weekOffset += 1
                                    HapticManager.selection()
                                }
                            }
                    )
                    .animation(.easeOut, value: weekOffset)
                    .padding(.vertical)
                    
                    List {
                        // Calendar Events Section
                        if !events.isEmpty {
                            Section {
                                HStack {
                                    Text("Events")
                                        
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Button(action: {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            isEventsExpanded.toggle()
                                        }
                                        HapticManager.selection()
                                    }) {
                                        Image(systemName: "chevron.right")
                                            .font(.caption)
                                            .rotationEffect(.degrees(isEventsExpanded ? 90 : 0))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                                
                                if isEventsExpanded {
                                    ForEach(events, id: \.eventIdentifier) { event in
                                        VStack(alignment: .leading, spacing: 2) {
                                            HStack(alignment: .center, spacing: 8) {
                                                // Replace calendar icon with vertical line
                                                RoundedRectangle(cornerRadius: 2)
                                                    .fill(Color(cgColor: event.calendar.cgColor))
                                                    .frame(width: 4)
                                                    .frame(height: 40) // Height to match two text rows
                                                
                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text(event.title)
                                                        .font(.body)
                                                        .foregroundColor(Color(cgColor: event.calendar.cgColor))
                                                    
                                                    HStack {
                                                        Text("\(formatTime(event.startDate)) to \(formatTime(event.endDate))")
                                                        if let location = event.location, !location.isEmpty {
                                                            Text("–")
                                                            Text(location)
                                                                .lineLimit(1)
                                                        }
                                                    }
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                                    .lineLimit(1)
                                                    
                                                    if let notes = event.notes, !notes.isEmpty {
                                                        Text(notes)
                                                            .font(.caption)
                                                            .foregroundStyle(.secondary)
                                                            .padding(.top, 2)
                                                    }
                                                }
                                            }
                                        }
                                        .padding(.vertical, 4)
                                        .listRowSeparator(.hidden)
                                        .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 4, trailing: 120))
                                        .listRowBackground(Color.clear)
                                    }
                                }
                            }
                        }
                        
                        // Reminders Section
                        if !reminders.isEmpty {
                            Section {
                                HStack {
                                    Text("Reminders")
                                        
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Button(action: {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            isRemindersExpanded.toggle()
                                        }
                                        HapticManager.selection()
                                    }) {
                                        Image(systemName: "chevron.right")
                                            .font(.caption)
                                            .rotationEffect(.degrees(isRemindersExpanded ? 90 : 0))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                                
                                if isRemindersExpanded {
                                    ForEach(reminders, id: \.calendarItemIdentifier) { reminder in
                                        VStack(alignment: .leading, spacing: 2) {
                                            HStack {
                                                Image(systemName: checkboxSymbol(for: reminder))
                                                    .foregroundStyle(.secondary)
                                                    .font(.system(size: 18))
                                                    .onTapGesture {
                                                        toggleReminder(reminder)
                                                    }
                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text(reminder.title)
                                                        .font(.body)
                                                    
                                                    HStack(spacing: 4) {
                                                        Text(reminder.calendar.title)
                                                        if let dueDate = reminder.dueDateComponents?.date {
                                                            Text(formatTime(dueDate))
                                                                .foregroundStyle(isOverdue(dueDate) ? .red : .secondary)
                                                        }
                                                        if reminder.hasRecurrenceRules {
                                                            Image(systemName: "arrow.clockwise")
                                                                .font(.system(size: 12))
                                                                .foregroundStyle(.secondary)
                                                        }
                                                        if let notes = reminder.notes, !notes.isEmpty {
                                                            Image(systemName: "note.text")
                                                                .font(.system(size: 12))
                                                                .foregroundStyle(.secondary)
                                                        }
                                                    }
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                                    
                                                   
                                             
                                                }
                                            }
                                        }
                                        .padding(.vertical, 4)
                                        .listRowSeparator(.hidden)
                                        .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 4, trailing: 120))
                                        .listRowBackground(Color.clear)
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .scrollIndicators(.hidden)  // Add this line
                }
                .withBottomBlurArea()
                
                // Add floating action button
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button(action: {
                            HapticManager.selection()
                            showingComposer = true
                        }) {
                            Image(systemName: "plus")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 60, height: 30)
                        }
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.roundedRectangle(radius: 24))  // Changed from .capsule to .roundedRectangle with radius 4
                        .tint(Color.currentAccent)
                        .padding(.trailing, 20)
                    }
                    .padding(.bottom, 20)
                }
            }
            .sheet(isPresented: $showingComposer) {
                UniversalTaskComposerView(preloadedLists: preloadedLists)
                    .presentationDetents([.height(160)])
                    .presentationDragIndicator(.visible)
            }
            .navigationTitle(navigationTitle)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if Calendar.current.isDateInToday(selectedDate),
                       let temp = temperature,
                       let description = weatherDescription {
                        HStack(spacing: 8) {
                            Text("\(Int(round(temp)))°C")
                                .font(.subheadline)
                                .foregroundStyle(Color.currentAccent)
                            Image(systemName: weatherService.weatherSymbol(for: description))
                                .font(.subheadline)  // Add this line to match temperature text size
                                .foregroundStyle(Color.currentAccent)
                        }
                    }
                }
            }
            .task {
                // Use prefetched data for initial display
                await MainActor.run {
                    self.events = prefetchedEvents
                    self.reminders = prefetchedReminders
                }
                
                // Then fetch fresh data
                if Calendar.current.isDateInToday(selectedDate) {
                    await fetchWeather()
                }
                await fetchEvents(for: selectedDate)
                await fetchReminders(for: selectedDate)
            }
        }
        .onAppear {
            HapticManager.impact()
        }
        .background(Color.customBackground)
        .tint(.secondary)
        .customNavigationBarBackButtonTitle()
    }
    
    private func fetchEvents(for date: Date) async {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        
        let visibleCalendars = eventStore.calendars(for: .event)
            .filter { !hiddenCalendarIds.contains($0.calendarIdentifier) }
        
        let predicate = eventStore.predicateForEvents(
            withStart: startOfDay,
            end: endOfDay,
            calendars: visibleCalendars
        )
        
        let dayEvents = eventStore.events(matching: predicate)
            .sorted { $0.startDate < $1.startDate }
        
        await MainActor.run {
            self.events = dayEvents
        }
    }
    
    private func getMondayOfCurrentWeek() -> Date {
        let calendar = Calendar.current
        let today = Date()
        
        // Get the weekday component (1 is Sunday, 2 is Monday, etc.)
        let weekday = calendar.component(.weekday, from: today)
        
        // Calculate how many days we need to subtract to get to Monday
        let daysToSubtract = weekday == 1 ? 6 : weekday - 2
        
        // Get Monday by subtracting the calculated days
        return calendar.date(byAdding: .day, value: -daysToSubtract, to: today) ?? today
    }
    
    private func fetchReminders(for date: Date) async {
        do {
            let calendar = Calendar.current
            let startOfDay = calendar.startOfDay(for: date)
            let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
            
            let visibleCalendars = eventStore.calendars(for: .reminder)
                .filter { !hiddenListIds.contains($0.calendarIdentifier) }
            
            var dayReminders: [EKReminder] = []
            
            for reminderCalendar in visibleCalendars {
                let predicate = eventStore.predicateForReminders(in: [reminderCalendar])
                let fetchedReminders = try await withCheckedThrowingContinuation { continuation in
                    eventStore.fetchReminders(matching: predicate) { reminders in
                        if let reminders = reminders {
                            continuation.resume(returning: reminders)
                        } else {
                            continuation.resume(throwing: NSError(domain: "ReminderError", code: -1))
                        }
                    }
                }
                
                let filtered = fetchedReminders.filter { reminder in
                    guard let dueDate = reminder.dueDateComponents?.date else { return false }
                    return dueDate >= startOfDay && 
                           dueDate < endOfDay && 
                           !reminder.isCompleted
                }
                
                dayReminders.append(contentsOf: filtered)
            }
            
            let sortedReminders = dayReminders.sorted { first, second in
                guard let date1 = first.dueDateComponents?.date,
                      let date2 = second.dueDateComponents?.date else {
                    return false
                }
                return date1 < date2
            }
            
            await MainActor.run {
                self.reminders = sortedReminders
            }
        } catch {
            print("Error fetching reminders: \(error)")
        }
    }
    
    private func formatTime(_ date: Date) -> String {
        let calendar = Calendar.current
        let timeFormatter = DateFormatter()
        
        // Format time as "6pm" instead of "6:00 PM"
        timeFormatter.dateFormat = "ha"
        timeFormatter.amSymbol = "am"
        timeFormatter.pmSymbol = "pm"
        
        // Check if time is 12am
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        let is12am = hour == 0 && minute == 0
        
        // If it's 12am, show nothing for time
        if is12am {
            return ""
        }
        
        // Just return the time string
        return timeFormatter.string(from: date).lowercased()
    }
    
    private func checkboxSymbol(for reminder: EKReminder) -> String {
        if reminder.isCompleted {
            return "checkmark.square"
        }
        if reminder.hasRecurrenceRules {
            return "arrow.clockwise"
        }
        if reminder.priority != 0 {
            return "triangle"
        }
        return "square"
    }
    
    private func toggleReminder(_ reminder: EKReminder) {
        reminder.isCompleted = !reminder.isCompleted
        if reminder.isCompleted {
            reminder.completionDate = Date()
        } else {
            reminder.completionDate = nil
        }
        
        do {
            try eventStore.save(reminder, commit: true)
            HapticManager.selection()
            Task {
                await fetchReminders(for: selectedDate)
                await updateApplicationBadge(eventStore: eventStore)  // Add this line
            }
        } catch {
            print("Error saving reminder: \(error)")
        }
    }
    
    private func fetchWeather() async {
        do {
            let weather = try await weatherService.fetchWeather()
            await MainActor.run {
                temperature = weather.main.temp
                weatherDescription = weather.weather.first?.description
            }
        } catch {
            print("Error fetching weather: \(error)")
        }
    }
    
    private func isOverdue(_ date: Date) -> Bool {
        let calendar = Calendar.current
        let now = Date()
        return date < calendar.startOfDay(for: now)
    }
}

struct DayButton: View {
    let date: Date
    let isSelected: Bool
    let action: () -> Void
    
    private let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter
    }()
    
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter
    }()
    
    private var isToday: Bool {
        Calendar.current.isDateInToday(date)
    }
    
    var body: some View {
        Button(action: action) {
            VStack {
                Text(dateFormatter.string(from: date))
                    .font(.title3.bold())
                    .foregroundStyle(isSelected ? .primary : .secondary)
                Text(dayFormatter.string(from: date).uppercased())
                    .font(.caption)
                    .foregroundStyle(isToday ? Color.currentAccent : (isSelected ? .primary : .secondary))  // Changed from accentOrange
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.currentAccent : .clear, lineWidth: 1)  // Changed from accentOrange
                    .padding(.horizontal, 6)
                    
            )
        }
        .buttonStyle(.plain)
    }
}

struct NextView: View {
    let eventStore = EKEventStore()
    @State private var reminders: [EKReminder] = []
    @AppStorage("hiddenLists") private var hiddenLists = Data()
    @AppStorage("manualReminderOrder") private var manualOrder = Data()
    @State private var showingComposer = false
    
    // Add this computed property
    private var preloadedLists: [EKCalendar] {
        eventStore.calendars(for: .reminder)
            .filter { !hiddenListIds.contains($0.calendarIdentifier) }
            .sorted { $0.title < $1.title }
    }
    
    private var hiddenListIds: Set<String> {
        if let decoded = try? JSONDecoder().decode(Set<String>.self, from: hiddenLists) {
            return decoded
        }
        return []
    }
    
    private var orderedReminders: [EKReminder] {
        if let orderData = try? JSONDecoder().decode([String].self, from: manualOrder) {
            let reminderDict = Dictionary(uniqueKeysWithValues: reminders.map { ($0.calendarItemIdentifier, $0) })
            
            var ordered: [EKReminder] = []
            for id in orderData {
                if let reminder = reminderDict[id] {
                    ordered.append(reminder)
                }
            }
            
            let orderedIds = Set(orderData)
            let remaining = reminders.filter { !orderedIds.contains($0.calendarItemIdentifier) }
            ordered.append(contentsOf: remaining)
            
            return ordered
        }
        return reminders
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.customBackground
                    .ignoresSafeArea()
                
                List {
                    ForEach(orderedReminders, id: \.calendarItemIdentifier) { reminder in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Image(systemName: checkboxSymbol(for: reminder))
                                    .foregroundStyle(.secondary)
                                    .font(.system(size: 18))
                                    .onTapGesture {
                                        toggleReminder(reminder)
                                    }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(reminder.title)
                                        .font(.body)
                                    
                                    HStack(spacing: 4) {
                                        Text(reminder.calendar.title)
                                        if let dueDate = reminder.dueDateComponents?.date {
                                            Text(formatTime(dueDate))
                                                .foregroundStyle(isOverdue(dueDate) ? .red : .secondary)
                                        }
                                        if reminder.hasRecurrenceRules {
                                            Image(systemName: "arrow.clockwise")
                                                .font(.system(size: 12))
                                                .foregroundStyle(.secondary)
                                        }
                                        if let notes = reminder.notes, !notes.isEmpty {
                                            Image(systemName: "note.text")
                                                .font(.system(size: 12))
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 4, trailing: 120))
                        .listRowBackground(Color.clear)
                    }
                    .onMove { from, to in
                        var updatedOrder = orderedReminders.map { $0.calendarItemIdentifier }
                        updatedOrder.move(fromOffsets: from, toOffset: to)
                        if let encoded = try? JSONEncoder().encode(updatedOrder) {
                            manualOrder = encoded
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .scrollIndicators(.hidden)
                
                // Floating action button
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button(action: {
                            HapticManager.selection()
                            showingComposer = true
                        }) {
                            Image(systemName: "plus")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 60, height: 30)
                        }
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.capsule)
                        .tint(Color.currentAccent)
                        .padding(.trailing, 20)
                    }
                    .padding(.bottom, 20)
                }
            }
        }
        .sheet(isPresented: $showingComposer) {
            UniversalTaskComposerView(preloadedLists: preloadedLists)
                .presentationDetents([.height(160)])
                    .presentationDragIndicator(.visible)
        }
        .navigationTitle("Next")
        .task {
            await fetchTodayReminders()
        }
        .background(Color.customBackground)
    }
    
    // Add these functions inside NextView:

    private func checkboxSymbol(for reminder: EKReminder) -> String {
        if reminder.isCompleted {
            return "checkmark.square"
        }
        if reminder.hasRecurrenceRules {
            return "arrow.clockwise"
        }
        if reminder.priority != 0 {
            return "triangle"
        }
        return "square"
    }

    private func formatTime(_ date: Date) -> String {
        let calendar = Calendar.current
        let now = Date()
        let timeFormatter = DateFormatter()
        let dateFormatter = DateFormatter()
        
        // Check if time is 12am
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        let is12am = hour == 0 && minute == 0
        
        // Format time as "6pm" instead of "6:00 PM"
        timeFormatter.dateFormat = "ha"
        timeFormatter.amSymbol = "am"
        timeFormatter.pmSymbol = "pm"
        let timeString = is12am ? "" : timeFormatter.string(from: date).lowercased()
        
        // If the date is today, only show time (unless it's 12am)
        if calendar.isDate(date, inSameDayAs: now) {
            return timeString
        }
        
        // Format date as "8th Nov"
        dateFormatter.dateFormat = "d'th' MMM"
        // Handle special cases for 1st, 2nd, 3rd
        let day = calendar.component(.day, from: date)
        let suffix: String
        switch day {
        case 1, 21, 31: suffix = "st"
        case 2, 22: suffix = "nd"
        case 3, 23: suffix = "rd"
        default: suffix = "th"
        }
        dateFormatter.dateFormat = "d'\(suffix)' MMM"
        
        // If it's 12am, only show the date
        if is12am {
            return dateFormatter.string(from: date)
        }
        
        // Otherwise show date and time
        return "\(dateFormatter.string(from: date)), \(timeString)"
    }

    private func isOverdue(_ date: Date) -> Bool {
        let calendar = Calendar.current
        let now = Date()
        return date < calendar.startOfDay(for: now)
    }

    private func toggleReminder(_ reminder: EKReminder) {
        reminder.isCompleted = !reminder.isCompleted
        if reminder.isCompleted {
            reminder.completionDate = Date()
        } else {
            reminder.completionDate = nil
        }
        
        do {
            try eventStore.save(reminder, commit: true)
            HapticManager.selection()
            Task {
                await fetchTodayReminders()
                await updateApplicationBadge(eventStore: eventStore)
            }
        } catch {
            print("Error saving reminder: \(error)")
        }
    }

    private func fetchTodayReminders() async {
        do {
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: Date())
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
            
            let visibleCalendars = eventStore.calendars(for: .reminder)
                .filter { !hiddenListIds.contains($0.calendarIdentifier) }
            
            var todayReminders: [EKReminder] = []
            
            for reminderCalendar in visibleCalendars {
                let predicate = eventStore.predicateForReminders(in: [reminderCalendar])
                let fetchedReminders = try await withCheckedThrowingContinuation { continuation in
                    eventStore.fetchReminders(matching: predicate) { reminders in
                        if let reminders = reminders {
                            continuation.resume(returning: reminders)
                        } else {
                            continuation.resume(throwing: NSError(domain: "ReminderError", code: -1))
                        }
                    }
                }
                
                let filtered = fetchedReminders.filter { reminder in
                    guard let dueDate = reminder.dueDateComponents?.date else { return false }
                    return dueDate >= today && 
                           dueDate < tomorrow && 
                           !reminder.isCompleted
                }
                
                todayReminders.append(contentsOf: filtered)
            }
            
            let sortedReminders = todayReminders.sorted { first, second in
                guard let date1 = first.dueDateComponents?.date,
                      let date2 = second.dueDateComponents?.date else {
                    return false
                }
                return date1 < date2
            }
            
            await MainActor.run {
                self.reminders = sortedReminders
            }
        } catch {
            print("Error fetching reminders: \(error)")
        }
    }
}

struct AllTasksView: View {
    let eventStore = EKEventStore()
    @State private var reminders: [EKReminder] = []
    @AppStorage("hiddenLists") private var hiddenLists = Data()
    @State private var showingComposer = false
    
    // Add this computed property
    private var preloadedLists: [EKCalendar] {
        eventStore.calendars(for: .reminder)
            .filter { !hiddenListIds.contains($0.calendarIdentifier) }
            .sorted { $0.title < $1.title }
    }
    
    private var hiddenListIds: Set<String> {
        if let decoded = try? JSONDecoder().decode(Set<String>.self, from: hiddenLists) {
            return decoded
        }
        return []
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.customBackground
                    .ignoresSafeArea()
                
                List {
                    ForEach(reminders, id: \.calendarItemIdentifier) { reminder in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Image(systemName: checkboxSymbol(for: reminder))
                                    .foregroundStyle(.secondary)
                                    .font(.system(size: 18))
                                    .onTapGesture {
                                        toggleReminder(reminder)
                                    }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(reminder.title)
                                        .font(.body)
                                    
                                    HStack(spacing: 4) {
                                        Text(reminder.calendar.title)
                                        if let dueDate = reminder.dueDateComponents?.date {
                                            Text(formatTime(dueDate))
                                                .foregroundStyle(isOverdue(dueDate) ? .red : .secondary)
                                        }
                                        if reminder.hasRecurrenceRules {
                                            Image(systemName: "arrow.clockwise")
                                                .font(.system(size: 12))
                                                .foregroundStyle(.secondary)
                                        }
                                        if let notes = reminder.notes, !notes.isEmpty {
                                            Image(systemName: "note.text")
                                                .font(.system(size: 12))
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 4, trailing: 120))  // Changed trailing from 16 to 120
                        .listRowBackground(Color.clear)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .scrollIndicators(.hidden)  // Add this line
                
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button(action: {
                            HapticManager.selection()
                            showingComposer = true
                        }) {
                            Image(systemName: "plus")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 60, height: 30)  // Changed from 28x28 to 60x30
                        }
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.capsule)
                        .tint(Color.currentAccent)  // Changed from accentOrange
                        .padding(.trailing, 20)
                    }
                    .padding(.bottom, 20)
                }
            }
            .sheet(isPresented: $showingComposer) {
                UniversalTaskComposerView(preloadedLists: preloadedLists)
                    .presentationDetents([.height(160)])
                        .presentationDragIndicator(.visible)
            }
            .navigationTitle("All Tasks")
            .task {
                await fetchAllReminders()
            }
        }
        .onAppear {
            HapticManager.impact()
        }
        .background(Color.customBackground)
        .tint(.secondary)
        .customNavigationBarBackButtonTitle()
    }
    
    private func fetchAllReminders() async {
        do {
            let visibleCalendars = eventStore.calendars(for: .reminder)
                .filter { !hiddenListIds.contains($0.calendarIdentifier) }
            var allReminders: [EKReminder] = []
            
            for calendar in visibleCalendars {
                let predicate = eventStore.predicateForReminders(in: [calendar])
                let fetchedReminders = try await withCheckedThrowingContinuation { continuation in
                    eventStore.fetchReminders(matching: predicate) { reminders in
                        if let reminders = reminders {
                            continuation.resume(returning: reminders)
                        } else {
                            continuation.resume(throwing: NSError(domain: "ReminderError", code: -1))
                        }
                    }
                }
                
                // Add incomplete reminders to our array
                allReminders.append(contentsOf: fetchedReminders.filter { !$0.isCompleted })
            }
            
            // Sort all reminders by due date
            let sortedReminders = allReminders.sorted { first, second in
                guard let date1 = first.dueDateComponents?.date,
                      let date2 = second.dueDateComponents?.date else {
                    return false
                }
                return date1 < date2
            }
            
            await MainActor.run {
                self.reminders = sortedReminders
            }
        } catch {
            print("Error fetching reminders: \(error)")
        }
    }
    
    private func formatTime(_ date: Date) -> String {
        let calendar = Calendar.current
        let now = Date()
        let timeFormatter = DateFormatter()
        let dateFormatter = DateFormatter()
        
        // Check if time is 12am
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        let is12am = hour == 0 && minute == 0
        
        // Format time as "6pm" instead of "6:00 PM"
        timeFormatter.dateFormat = "ha"
        timeFormatter.amSymbol = "am"
        timeFormatter.pmSymbol = "pm"
        let timeString = is12am ? "" : timeFormatter.string(from: date).lowercased()
        
        // If the date is today, only show time (unless it's 12am)
        if calendar.isDate(date, inSameDayAs: now) {
            return timeString
        }
        
        // Format date as "8th Nov"
        dateFormatter.dateFormat = "d'th' MMM"
        // Handle special cases for 1st, 2nd, 3rd
        let day = calendar.component(.day, from: date)
        let suffix: String
        switch day {
        case 1, 21, 31: suffix = "st"
        case 2, 22: suffix = "nd"
        case 3, 23: suffix = "rd"
        default: suffix = "th"
        }
        dateFormatter.dateFormat = "d'\(suffix)' MMM"
        
        // If it's 12am, only show the date
        if is12am {
            return dateFormatter.string(from: date)
        }
        
        // Otherwise show date and time
        return "\(dateFormatter.string(from: date)), \(timeString)"
    }
    
    private func checkboxSymbol(for reminder: EKReminder) -> String {
        if reminder.isCompleted {
            return "checkmark.square"
        }
        if reminder.hasRecurrenceRules {
            return "arrow.clockwise"
        }
        if reminder.priority != 0 {
            return "triangle"
        }
        return "square"
    }
    
    private func toggleReminder(_ reminder: EKReminder) {
        reminder.isCompleted = !reminder.isCompleted
        if reminder.isCompleted {
            reminder.completionDate = Date()
        } else {
            reminder.completionDate = nil
        }
        
        do {
            try eventStore.save(reminder, commit: true)
            HapticManager.selection()
            Task {
                await fetchAllReminders()
                await updateApplicationBadge(eventStore: eventStore)  // Add this line
            }
        } catch {
            print("Error saving reminder: \(error)")
        }
    }
    
    private func isOverdue(_ date: Date) -> Bool {
        let calendar = Calendar.current
        let now = Date()
        return date < calendar.startOfDay(for: now)
    }
}

struct LogbookView: View {
    let eventStore = EKEventStore()
    @State private var reminders: [EKReminder] = []
    @AppStorage("hiddenLists") private var hiddenLists = Data()
    @State private var showingComposer = false
    
    private var hiddenListIds: Set<String> {
        if let decoded = try? JSONDecoder().decode(Set<String>.self, from: hiddenLists) {
            return decoded
        }
        return []
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.customBackground
                    .ignoresSafeArea()
                
                List {
                    ForEach(reminders, id: \.calendarItemIdentifier) { reminder in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Image(systemName: checkboxSymbol(for: reminder))
                                    .foregroundStyle(.secondary)
                                    .font(.system(size: 18))
                                    .onTapGesture {
                                        toggleReminder(reminder)
                                    }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(reminder.title)
                                        .font(.body)
                                        .foregroundStyle(.secondary)  // Add this line to make completed task titles gray
                                    
                                    HStack(spacing: 4) {
                                        Text(reminder.calendar.title)
                                        if let dueDate = reminder.dueDateComponents?.date {
                                            Text(formatTime(dueDate))
                                                .foregroundStyle(isOverdue(dueDate) ? .red : .secondary)
                                        }
                                        if reminder.hasRecurrenceRules {
                                            Image(systemName: "arrow.clockwise")
                                                .font(.system(size: 12))
                                                .foregroundStyle(.secondary)
                                        }
                                        if let notes = reminder.notes, !notes.isEmpty {
                                            Image(systemName: "note.text")
                                                .font(.system(size: 12))
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    
                                
                                }
                            }
                        }
                        .padding(.vertical, 4)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 4, trailing: 120))  // Changed trailing from 16 to 120
                        .listRowBackground(Color.clear)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .scrollIndicators(.hidden)  // Add this line
                .navigationTitle("Logbook")
                .task {
                    await fetchCompletedReminders()
                }
            }
            .onAppear {
                HapticManager.impact()
            }
            .background(Color.customBackground)
            .tint(.secondary)
            .customNavigationBarBackButtonTitle()
        }
    }
    
    private func fetchCompletedReminders() async {
        do {
            let visibleCalendars = eventStore.calendars(for: .reminder)
                .filter { !hiddenListIds.contains($0.calendarIdentifier) }
            var allReminders: [EKReminder] = []
            
            for calendar in visibleCalendars {
                let predicate = eventStore.predicateForReminders(in: [calendar])
                let fetchedReminders = try await withCheckedThrowingContinuation { continuation in
                    eventStore.fetchReminders(matching: predicate) { reminders in
                        if let reminders = reminders {
                            continuation.resume(returning: reminders)
                        } else {
                            continuation.resume(throwing: NSError(domain: "ReminderError", code: -1))
                        }
                    }
                }
                
                // Add completed reminders to our array
                allReminders.append(contentsOf: fetchedReminders.filter { $0.isCompleted })
            }
            
            // Sort all reminders by completion date (most recent first)
            let sortedReminders = allReminders.sorted { first, second in
                guard let date1 = first.completionDate,
                      let date2 = second.completionDate else {
                    return false
                }
                return date1 > date2 // Reverse order to show most recent first
            }
            
            await MainActor.run {
                self.reminders = sortedReminders
            }
        } catch {
            print("Error fetching reminders: \(error)")
        }
    }
    
    private func formatTime(_ date: Date) -> String {
        let calendar = Calendar.current
        let now = Date()
        let timeFormatter = DateFormatter()
        let dateFormatter = DateFormatter()
        
        // Check if time is 12am
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        let is12am = hour == 0 && minute == 0
        
        // Format time as "6pm" instead of "6:00 PM"
        timeFormatter.dateFormat = "ha"
        timeFormatter.amSymbol = "am"
        timeFormatter.pmSymbol = "pm"
        let timeString = is12am ? "" : timeFormatter.string(from: date).lowercased()
        
        // If the date is today, only show time (unless it's 12am)
        if calendar.isDate(date, inSameDayAs: now) {
            return timeString
        }
        
        // Format date as "8th Nov"
        dateFormatter.dateFormat = "d'th' MMM"
        // Handle special cases for 1st, 2nd, 3rd
        let day = calendar.component(.day, from: date)
        let suffix: String
        switch day {
        case 1, 21, 31: suffix = "st"
        case 2, 22: suffix = "nd"
        case 3, 23: suffix = "rd"
        default: suffix = "th"
        }
        dateFormatter.dateFormat = "d'\(suffix)' MMM"
        
        // If it's 12am, only show the date
        if is12am {
            return dateFormatter.string(from: date)
        }
        
        // Otherwise show date and time
        return "\(dateFormatter.string(from: date)), \(timeString)"
    }
    
    private func checkboxSymbol(for reminder: EKReminder) -> String {
        if reminder.isCompleted {
            return "checkmark.square"
        }
        if reminder.hasRecurrenceRules {
            return "arrow.clockwise"
        }
        if reminder.priority != 0 {
            return "triangle"
        }
        return "square"
    }
    
    private func toggleReminder(_ reminder: EKReminder) {
        reminder.isCompleted = !reminder.isCompleted
        if reminder.isCompleted {
            reminder.completionDate = Date()
        } else {
            reminder.completionDate = nil
        }
        
        do {
            try eventStore.save(reminder, commit: true)
            HapticManager.selection()
            Task {
                await fetchCompletedReminders()
                await updateApplicationBadge(eventStore: eventStore)  // Add this line
            }
        } catch {
            print("Error saving reminder: \(error)")
        }
    }
    
    private func isOverdue(_ date: Date) -> Bool {
        let calendar = Calendar.current
        let now = Date()
        return date < calendar.startOfDay(for: now)
    }
}

struct PreferencesView: View {
    @Environment(\.dismiss) private var dismiss
    let eventStore = EKEventStore()
    @AppStorage("hiddenCalendars") private var hiddenCalendars = Data()
    @AppStorage("hiddenLists") private var hiddenLists = Data()
    @AppStorage("AccentColorIndex") private var selectedColorIndex = 0
    @State private var hiddenCalendarSet: Set<String> = []
    @State private var hiddenListSet: Set<String> = []
    var onListsChanged: (() -> Void)? = nil
    @AppStorage("showBadges") private var showBadges = true  // Default to true
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Text("Show Badges")
                        Spacer()
                        Toggle("", isOn: $showBadges)
                            .toggleStyle(CircleToggleStyle())  // Add this line to use our custom style
                            .onChange(of: showBadges) { newValue in
                                Task {
                                    if !newValue {
                                        // Clear badge if disabled
                                        await MainActor.run {
                                            UNUserNotificationCenter.current().setBadgeCount(0) { error in
                                                if let error = error {
                                                    print("Error clearing badge count: \(error)")
                                                }
                                            }
                                        }
                                    } else {
                                        // Update badge if enabled
                                        await updateApplicationBadge(eventStore: eventStore)
                                    }
                                }
                                HapticManager.selection()
                            }
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                } header: {
                    Text("General")
                        .padding(.leading, -20)  // Add this line
                }
                
                Section {
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 16) {
                        ForEach(Color.accentColors.indices, id: \.self) { index in
                            VStack(spacing: 4) {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.accentColors[index].color)
                                    .frame(height: 50)
                                    .overlay(
                                        Group {
                                            if index == selectedColorIndex {
                                                Image(systemName: "swatchpalette")
                                                    .foregroundStyle(.white)
                                                    .font(.system(size: 26))  // Changed from 30 to 26
                                            }
                                        }
                                    )
                                Text(Color.accentColors[index].name)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedColorIndex = index
                                HapticManager.selection()
                            }
                        }
                    }
                    .padding(.vertical, 8)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)  // Add this line
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                } header: {
                    Text("Accent Color")
                        .padding(.leading, -20)  // Add this line
                }
                
                Section {
                    ForEach(eventStore.calendars(for: .event), id: \.calendarIdentifier) { calendar in
                        HStack {
                            Circle()
                                .fill(Color(cgColor: calendar.cgColor))
                                .frame(width: 12, height: 12)
                            Text(calendar.title)
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { !hiddenCalendarSet.contains(calendar.calendarIdentifier) },
                                set: { isVisible in
                                    if isVisible {
                                        hiddenCalendarSet.remove(calendar.calendarIdentifier)
                                    } else {
                                        hiddenCalendarSet.insert(calendar.calendarIdentifier)
                                    }
                                    if let encoded = try? JSONEncoder().encode(hiddenCalendarSet) {
                                        hiddenCalendars = encoded
                                    }
                                    HapticManager.selection()
                                }
                            ))
                            .toggleStyle(CircleToggleStyle())  // Apply the custom style
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)  // Add this line
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    }
                } header: {
                    Text("Calendars")
                        .padding(.leading, -20)  // Add this line
                }
                
                Section {
                    ForEach(eventStore.calendars(for: .reminder), id: \.calendarIdentifier) { list in
                        HStack {
                            Circle()
                                .fill(Color(cgColor: list.cgColor))
                                .frame(width: 12, height: 12)
                            Text(list.title)
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { !hiddenListSet.contains(list.calendarIdentifier) },
                                set: { isVisible in
                                    if isVisible {
                                        hiddenListSet.remove(list.calendarIdentifier)
                                    } else {
                                        hiddenListSet.insert(list.calendarIdentifier)
                                    }
                                    if let encoded = try? JSONEncoder().encode(hiddenListSet) {
                                        hiddenLists = encoded
                                    }
                                    HapticManager.selection()
                                    onListsChanged?()
                                }
                            ))
                            .toggleStyle(CircleToggleStyle())  // Apply the custom style
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)  // Add this line
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    }
                } header: {
                    Text("Reminder Lists")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                        .padding(.leading, -20)  // Add this line
                }
            }
            .navigationTitle("Preferences")
            .scrollContentBackground(.hidden)  // Make sure this is present
            .scrollIndicators(.hidden)  // Add this line
        }
        .onAppear {
            // Load saved data when view appears
            if let decoded = try? JSONDecoder().decode(Set<String>.self, from: hiddenCalendars) {
                hiddenCalendarSet = decoded
            }
            if let decoded = try? JSONDecoder().decode(Set<String>.self, from: hiddenLists) {
                hiddenListSet = decoded
            }
            HapticManager.impact()
        }
        .background(Color.customBackground)
        .customNavigationBarBackButtonTitle()
        .tint(.secondary)
    }
}

struct ListView: View {
    let calendar: EKCalendar
    let eventStore = EKEventStore()
    @State private var reminders: [EKReminder] = []
    @State private var completingReminders: Set<String> = []
    @State private var showingComposer = false
    
    // Add this computed property
    private var preloadedLists: [EKCalendar] {
        eventStore.calendars(for: .reminder)
            .filter { !hiddenListIds.contains($0.calendarIdentifier) }
            .sorted { $0.title < $1.title }
    }
    
    private var hiddenListIds: Set<String> {
        if let decoded = try? JSONDecoder().decode(Set<String>.self, from: Data(UserDefaults.standard.data(forKey: "hiddenLists") ?? Data())) {
            return decoded
        }
        return []
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.customBackground
                    .ignoresSafeArea()
                
                List {
                    ForEach(reminders, id: \.calendarItemIdentifier) { reminder in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Image(systemName: checkboxSymbol(for: reminder))
                                    .foregroundStyle(.secondary)
                                    .font(.system(size: 18))
                                    .onTapGesture {
                                        toggleReminder(reminder)
                                    }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(reminder.title)
                                        .font(.body)
                                    
                                    HStack(spacing: 4) {
                                        Text(reminder.calendar.title)
                                        if let dueDate = reminder.dueDateComponents?.date {
                                            Text(formatTime(dueDate))
                                                .foregroundStyle(isOverdue(dueDate) ? .red : .secondary)
                                        }
                                        if reminder.hasRecurrenceRules {
                                            Image(systemName: "arrow.clockwise")
                                                .font(.system(size: 12))
                                                .foregroundStyle(.secondary)
                                        }
                                        if let notes = reminder.notes, !notes.isEmpty {
                                            Image(systemName: "note.text")
                                                .font(.system(size: 12))
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    
                                   
                                }
                            }
                        }
                        .padding(.vertical, 4)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 4, trailing: 120))  // Changed trailing from 16 to 120
                        .listRowBackground(Color.clear)
                        .opacity(completingReminders.contains(reminder.calendarItemIdentifier) ? 0.3 : 1.0)
                        .animation(.easeOut(duration: 0.2), value: completingReminders.contains(reminder.calendarItemIdentifier))
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .scrollIndicators(.hidden)  // Add this line
                
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button(action: {
                            HapticManager.selection()
                            showingComposer = true
                        }) {
                            Image(systemName: "plus")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 60, height: 30)  // Changed from 28x28 to 60x30
                        }
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.capsule)
                        .tint(Color.currentAccent)  // Changed from accentOrange
                        .padding(.trailing, 20)
                    }
                    .padding(.bottom, 20)
                }
            }
            .sheet(isPresented: $showingComposer) {
                UniversalTaskComposerView(preloadedLists: preloadedLists)
                    .presentationDetents([.height(160)])
                    .presentationDragIndicator(.visible)
            }
            .navigationTitle(calendar.title)
            .task {
                await fetchReminders()
            }
        }
        .onAppear {
            HapticManager.impact()
        }
        .tint(.secondary)
        .customNavigationBarBackButtonTitle()
    }
    
    private func fetchReminders() async {
        do {
            let predicate = eventStore.predicateForReminders(in: [calendar])
            let fetchedReminders = try await withCheckedThrowingContinuation { continuation in
                eventStore.fetchReminders(matching: predicate) { reminders in
                    if let reminders = reminders {
                        continuation.resume(returning: reminders)
                    } else {
                        continuation.resume(throwing: NSError(domain: "ReminderError", code: -1))
                    }
                }
            }
            
            // Filter for incomplete reminders and sort by due date
            let incompleteReminders = fetchedReminders
                .filter { !$0.isCompleted }
                .sorted { first, second in
                    guard let date1 = first.dueDateComponents?.date,
                          let date2 = second.dueDateComponents?.date else {
                        return false
                    }
                    return date1 < date2
                }
            
            await MainActor.run {
                self.reminders = incompleteReminders
            }
        } catch {
            print("Error fetching reminders: \(error)")
        }
    }
    
    private func formatTime(_ date: Date) -> String {
        let calendar = Calendar.current
        let now = Date()
        let timeFormatter = DateFormatter()
        let dateFormatter = DateFormatter()
        
        // Check if time is 12am
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        let is12am = hour == 0 && minute == 0
        
        // Format time as "6pm" instead of "6:00 PM"
        timeFormatter.dateFormat = "ha"
        timeFormatter.amSymbol = "am"
        timeFormatter.pmSymbol = "pm"
        let timeString = is12am ? "" : timeFormatter.string(from: date).lowercased()
        
        // If the date is today, only show time (unless it's 12am)
        if calendar.isDate(date, inSameDayAs: now) {
            return timeString
        }
        
        // Format date as "8th Nov"
        dateFormatter.dateFormat = "d'th' MMM"
        // Handle special cases for 1st, 2nd, 3rd
        let day = calendar.component(.day, from: date)
        let suffix: String
        switch day {
        case 1, 21, 31: suffix = "st"
        case 2, 22: suffix = "nd"
        case 3, 23: suffix = "rd"
        default: suffix = "th"
        }
        dateFormatter.dateFormat = "d'\(suffix)' MMM"
        
        // If it's 12am, only show the date
        if is12am {
            return dateFormatter.string(from: date)
        }
        
        // Otherwise show date and time
        return "\(dateFormatter.string(from: date)), \(timeString)"
    }
    
    private func checkboxSymbol(for reminder: EKReminder) -> String {
        if reminder.isCompleted {
            return "checkmark.square"
        }
        if reminder.hasRecurrenceRules {
            return "arrow.clockwise"
        }
        if reminder.priority != 0 {
            return "triangle"
        }
        return "square"
    }
    
    private func toggleReminder(_ reminder: EKReminder) {
        let reminderId = reminder.calendarItemIdentifier
        
        // If completing the task
        if !reminder.isCompleted {
            completingReminders.insert(reminderId)
            
            // Delay the actual completion to allow for animation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                reminder.isCompleted = true
                reminder.completionDate = Date()
                
                do {
                    try eventStore.save(reminder, commit: true)
                    HapticManager.selection()
                    Task {
                        await fetchReminders()
                        await updateApplicationBadge(eventStore: eventStore)  // Add this line
                    }
                } catch {
                    print("Error saving reminder: \(error)")
                }
            }
        } else {
            // If uncompleting, do it immediately
            reminder.isCompleted = false
            reminder.completionDate = nil
            
            do {
                try eventStore.save(reminder, commit: true)
                HapticManager.selection()
                Task {
                    await fetchReminders()
                }
            } catch {
                print("Error saving reminder: \(error)")
            }
        }
    }
    
    private func isOverdue(_ date: Date) -> Bool {
        let calendar = Calendar.current
        let now = Date()
        return date < calendar.startOfDay(for: now)
    }
}
    
    private func isOverdue(_ date: Date) -> Bool {
        let calendar = Calendar.current
        let now = Date()
        return date < calendar.startOfDay(for: now)
    }


struct ContentView: View {
    // Add this property at the top of ContentView
    @State private var preloadedComposer: TaskComposerView? = nil  // Change from Bool to TaskComposerView?
    
    private let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter
    }()
    
    private let yearFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy"
        return formatter
    }()
    
    private func daySuffix(for day: Int) -> String {
        switch day {
        case 1, 21, 31: return "st"
        case 2, 22: return "nd"
        case 3, 23: return "rd"
        default: return "th"
        }
    }
    
    private func formattedDate() -> String {
        let date = Date()
        let day = Calendar.current.component(.day, from: date)
        let suffix = daySuffix(for: day)
        
        let formatter = DateFormatter()
        formatter.dateFormat = "d'\(suffix)' MMM"
        return formatter.string(from: date)
    }
    
    @State private var reminders: [EKReminder] = []
    @State private var events: [EKEvent] = []
    @State private var isAuthorized = false
    @State private var completingReminders: Set<String> = []
    private let eventStore = EKEventStore()
    @State private var reminderLists: [EKCalendar] = []
    
    @AppStorage("hiddenCalendars") private var hiddenCalendars = Data()
    @AppStorage("hiddenLists") private var hiddenLists = Data()
    
    private var hiddenCalendarIds: Set<String> {
        get {
            if let decoded = try? JSONDecoder().decode(Set<String>.self, from: hiddenCalendars) {
                return decoded
            }
            return []
        }
        set {
            if let encoded = try? JSONEncoder().encode(newValue) {
                hiddenCalendars = encoded
            }
        }
    }
    
    private var hiddenListIds: Set<String> {
        get {
            if let decoded = try? JSONDecoder().decode(Set<String>.self, from: hiddenLists) {
                return decoded
            }
            return []
        }
        set {
            if let encoded = try? JSONEncoder().encode(newValue) {
                hiddenLists = encoded
            }
        }
    }
    
    // Add these new properties
    private let agendaEventStore = EKEventStore()
    @State private var prefetchedEvents: [EKEvent] = []
    @State private var prefetchedReminders: [EKReminder] = []
    
    // Add this function to prefetch data
    private func prefetchAgendaData() async {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        
        // Fetch events
        let visibleCalendars = agendaEventStore.calendars(for: .event)
            .filter { !hiddenCalendarIds.contains($0.calendarIdentifier) }
        
        let predicate = agendaEventStore.predicateForEvents(
            withStart: today,
            end: tomorrow,
            calendars: visibleCalendars
        )
        
        let dayEvents = agendaEventStore.events(matching: predicate)
            .sorted { $0.startDate < $1.startDate }
        
        // Fetch reminders
        do {
            let visibleReminderCalendars = agendaEventStore.calendars(for: .reminder)
                .filter { !hiddenListIds.contains($0.calendarIdentifier) }
            
            var dayReminders: [EKReminder] = []
            
            for reminderCalendar in visibleReminderCalendars {
                let predicate = agendaEventStore.predicateForReminders(in: [reminderCalendar])
                let fetchedReminders = try await withCheckedThrowingContinuation { continuation in
                    agendaEventStore.fetchReminders(matching: predicate) { reminders in
                        if let reminders = reminders {
                            continuation.resume(returning: reminders)
                        } else {
                            continuation.resume(throwing: NSError(domain: "ReminderError", code: -1))
                        }
                    }
                }
                
                let filtered = fetchedReminders.filter { reminder in
                    guard let dueDate = reminder.dueDateComponents?.date else { return false }
                    return dueDate >= today && 
                           dueDate < tomorrow && 
                           !reminder.isCompleted
                }
                
                dayReminders.append(contentsOf: filtered)
            }
            
            let sortedReminders = dayReminders.sorted { first, second in
                guard let date1 = first.dueDateComponents?.date,
                      let date2 = second.dueDateComponents?.date else {
                    return false
                }
                return date1 < date2
            }
            
            await MainActor.run {
                self.prefetchedEvents = dayEvents
                self.prefetchedReminders = sortedReminders
            }
            
        } catch {
            print("Error prefetching reminders: \(error)")
        }
    }
    
    // Add these properties to ContentView
    @State private var preloadedComposerView: TaskComposerView? = nil
    @State private var preloadedLists: [EKCalendar] = []
    
    // Add this function to ContentView to preload the composer
    private func preloadComposer() {
        // Prefetch reminder lists
        let lists = eventStore.calendars(for: .reminder)
            .filter { !hiddenListIds.contains($0.calendarIdentifier) }
            .sorted { $0.title < $1.title }
        
        // Create and store the preloaded view
        Task { @MainActor in
            self.preloadedLists = lists
            self.preloadedComposer = TaskComposerView(preloadedLists: lists)
        }
    }
    
    // Add this new state variable
    @State private var showingUniversalComposer = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.customBackground
                    .ignoresSafeArea()
                
                List {
                    // Top menu items
                    Group {
                        NavigationLink {
                            NextView()
                                .onAppear {
                                    HapticManager.selection()
                                }
                        } label: {
                            Label {
                                Text("Next")
                                    .foregroundStyle(.primary)
                            } icon: {
                                Image(systemName: "bolt.horizontal")
                                    .foregroundStyle(Color(red: 255/255, green: 79/255, blue: 0/255))  // Updated to 255, 79, 0
                            }
                            .fontWeight(.semibold)
                        }
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 16))
                        .tint(.clear)
                        
                        NavigationLink {
                            AgendaView(prefetchedEvents: prefetchedEvents, 
                                      prefetchedReminders: prefetchedReminders)
                                .onAppear {
                                    HapticManager.selection()
                                }
                        } label: {
                            Label {
                                Text("Agenda")
                                    .foregroundStyle(.primary)
                            } icon: {
                                Image(systemName: "calendar")
                                    .foregroundStyle(Color(red: 178/255, green: 31/255, blue: 46/255))  // Changed from previous purple to new red
                            }
                            .fontWeight(.semibold)
                        }
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 16))
                        .tint(.clear)
                        
                        NavigationLink {
                            AllTasksView()
                                .onAppear {
                                    HapticManager.selection()
                                }
                        } label: {
                            Label {
                                Text("All tasks")
                                    .foregroundStyle(.primary)
                            } icon: {
                                Image(systemName: "square.stack")
                                    .foregroundStyle(Color(red: 68/255, green: 109/255, blue: 146/255))  // Updated to 68, 109, 146
                            }
                            .fontWeight(.semibold)
                        }
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 16))
                        .tint(.clear)
                        
                        NavigationLink {
                            LogbookView()
                                .onAppear {
                                    HapticManager.selection()
                                }
                        } label: {
                            Label {
                                Text("Logbook")
                                    .foregroundStyle(.primary)
                            } icon: {
                                Image(systemName: "checkmark.rectangle.stack.fill")
                                    .foregroundStyle(Color(red: 47/255, green: 91/255, blue: 42/255))  // Changed to new green color
                            }
                            .fontWeight(.semibold)
                        }
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 16))
                        .tint(.clear)
                    }
                    .listRowSeparator(.hidden)
                    
                    // Reminder Lists section
                    Section {
                        ForEach(reminderLists, id: \.calendarIdentifier) { list in
                            NavigationLink {
                                ListView(calendar: list)
                                    .onAppear {
                                        HapticManager.selection()
                                    }
                            } label: {
                                Label {
                                    Text(list.title)
                                        .foregroundStyle(.primary)
                                } icon: {
                                    Image(systemName: "number")  // Changed from "list.bullet.rectangle"
                                        .foregroundColor(Color(cgColor: list.cgColor))
                                }
                            }
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 16))
                            .tint(.clear)
                        }
                    } header: {
                        Text("Lists")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)
                            .padding(.leading, -20)  // Add this line
                    }
                    
                    // Preferences section
                    Section {
                        NavigationLink {
                            PreferencesView(onListsChanged: {
                                refreshLists()
                            })
                            .onAppear {
                                HapticManager.selection()
                            }
                        } label: {
                            Label {
                                Text("Preferences")
                                    .foregroundStyle(.primary)
                            } icon: {
                                Image(systemName: "switch.2")
                                    .foregroundStyle(Color(red: 66/255, green: 72/255, blue: 78/255))
                            }
                        }
                        
                        // Add new universal composer button
                        Button(action: {
                            HapticManager.selection()
                            showingUniversalComposer = true
                        }) {
                            Label {
                                Text("Add")
                                    .foregroundStyle(.primary)
                            } icon: {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundStyle(Color.currentAccent)
                            }
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 16))
                    .tint(.clear)
                }
                .scrollDisabled(true)
                .frame(maxHeight: .infinity, alignment: .top)
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
                .background(Color.sidebarBackground)  // Add this line to make the red background visible
                .navigationTitle(dayFormatter.string(from: Date()))
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        VStack(alignment: .trailing) {
                            Text(formattedDate())
                                .font(.subheadline)
                            Text(yearFormatter.string(from: Date()))
                                .font(.caption)
                        }
                        .foregroundStyle(.secondary)
                    }
                }
                .toolbarBackground(.hidden, for: .navigationBar)  // Add this line to make navigation bar transparent
                .task {  // Add this task modifier
                    await requestAccess()
                    if isAuthorized {
                        fetchReminderLists()
                    }
                }
            }
            .background(Color.customBackground)
            .dynamicTypeSize(...DynamicTypeSize.accessibility5)
            .tint(.secondary)
            .customNavigationBarBackButtonTitle()
        }
        .onAppear {
            HapticManager.impact()
            preloadComposer()  // Add this line
            // Enable screen idle timer
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .task {
            await updateApplicationBadge(eventStore: eventStore)
            await prefetchAgendaData()  // Add this line
        }
        .sheet(isPresented: $showingUniversalComposer) {
            UniversalTaskComposerView(preloadedLists: preloadedLists)
                .presentationDetents([.height(160)])  // Changed from 350 to 160
                .presentationDragIndicator(.visible)
        }
    }
    
    // Update the requestNotificationPermission function to be more explicit
    private func requestNotificationPermission() async {
        do {
            let notificationSettings = await UNUserNotificationCenter.current().notificationSettings()
            if notificationSettings.authorizationStatus == .notDetermined {
                let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.badge, .alert, .sound])
                if granted {
                    // Update badge immediately after getting permission
                    await updateApplicationBadge(eventStore: eventStore)
                }
            }
        } catch {
            print("Error requesting notification permission: \(error)")
        }
    }
    
    private func requestAccess() async {
        do {
            if #available(iOS 17.0, *) {
                // Request both Reminders and Calendar access
                async let remindersAuth = eventStore.requestFullAccessToReminders()
                async let calendarAuth = eventStore.requestFullAccessToEvents()
                
                let (reminderAccess, calendarAccess) = try await (remindersAuth, calendarAuth)
                isAuthorized = reminderAccess && calendarAccess
            } else {
                // For older iOS versions
                async let remindersAuth = eventStore.requestAccess(to: .reminder)
                async let calendarAuth = eventStore.requestAccess(to: .event)
                
                let (reminderAccess, calendarAccess) = try await (remindersAuth, calendarAuth)
                isAuthorized = reminderAccess && calendarAccess
            }
        } catch {
            print("Error requesting access: \(error)")
            isAuthorized = false
        }
    }
    
    private func fetchEvents() async {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        
        let visibleCalendars = eventStore.calendars(for: .event)
            .filter { !hiddenCalendarIds.contains($0.calendarIdentifier) }
        
        let predicate = eventStore.predicateForEvents(
            withStart: today,
            end: tomorrow,
            calendars: visibleCalendars
        )
        
        let todayEvents = eventStore.events(matching: predicate)
            .sorted { $0.startDate < $1.startDate }
        
        self.events = todayEvents
    }
    
    private func fetchReminders() async {
        do {
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: Date())
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
            
            let visibleCalendars = eventStore.calendars(for: .reminder)
                .filter { !hiddenListIds.contains($0.calendarIdentifier) }
            
            var allReminders: [EKReminder] = []
            
            for reminderCalendar in visibleCalendars {
                let predicate = eventStore.predicateForReminders(in: [reminderCalendar])
                let calendarReminders = try await withCheckedThrowingContinuation { continuation in
                    eventStore.fetchReminders(matching: predicate) { reminders in
                        if let reminders = reminders {
                            continuation.resume(returning: reminders)
                        } else {
                            continuation.resume(throwing: NSError(domain: "ReminderError", code: -1))
                        }
                    }
                }
                
                // Filter reminders for today and not completed
                let todayReminders = calendarReminders.filter { reminder in
                    guard let dueDate = reminder.dueDateComponents?.date else { return false }
                    return dueDate >= today && 
                           dueDate < tomorrow && 
                           !reminder.isCompleted
                }
                
                allReminders.append(contentsOf: todayReminders)
            }
            
            // Sort reminders by due date
            self.reminders = allReminders.sorted { first, second in
                guard let date1 = first.dueDateComponents?.date,
                      let date2 = second.dueDateComponents?.date else {
                    return false
                }
                return date1 < date2
            }
        } catch {
            print("Error fetching reminders: \(error)")
        }
    }
    
    private func formatDueDate(_ date: Date) -> String {
        let timeFormatter = DateFormatter()
        timeFormatter.dateStyle = .none
        timeFormatter.timeStyle = .short
        return timeFormatter.string(from: date)
    }
    
    // Helper function to format event time
    private func formatEventTime(_ event: EKEvent) -> String {
        let timeFormatter = DateFormatter()
        timeFormatter.dateStyle = .none
        timeFormatter.timeStyle = .short
        return "\(timeFormatter.string(from: event.startDate)) - \(timeFormatter.string(from: event.endDate)))"
    }
    
    private func fetchReminderLists() {
        let lists = eventStore.calendars(for: .reminder)
            .filter { !hiddenListIds.contains($0.calendarIdentifier) }
            .sorted { $0.title < $1.title }
        self.reminderLists = lists
    }
    
    // Update refreshLists to be async and modify state directly
    private func refreshLists() {
        Task {
            let lists = eventStore.calendars(for: .reminder)
                .filter { !hiddenListIds.contains($0.calendarIdentifier) }
                .sorted { $0.title < $1.title }
            await MainActor.run {
                self.reminderLists = lists
            }
        }
    }
    
    private func getWindowScene() -> UIWindowScene? {
        return UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive && $0 is UIWindowScene }) as? UIWindowScene
    }
    
    private func toggleReminder(_ reminder: EKReminder) {
        let reminderId = reminder.calendarItemIdentifier
        
        // If completing the task
        if !reminder.isCompleted {
            completingReminders.insert(reminderId)
            
            // Delay the actual completion to allow for animation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                reminder.isCompleted = true
                reminder.completionDate = Date()
                
                do {
                    try eventStore.save(reminder, commit: true)
                    HapticManager.selection()
                    Task {
                        await fetchReminders()
                        await updateApplicationBadge(eventStore: eventStore)  // Add this line
                    }
                } catch {
                    print("Error saving reminder: \(error)")
                }
            }
        } else {
            // If uncompleting, do it immediately
            reminder.isCompleted = false
            reminder.completionDate = nil
            
            do {
                try eventStore.save(reminder, commit: true)
                HapticManager.selection()
                Task {
                    await fetchReminders()
                }
            } catch {
                print("Error saving reminder: \(error)")
            }
        }
    }
}

struct TaskComposerView: View {
    @Environment(\.dismiss) private var dismiss
    let eventStore = EKEventStore()
    
    @State private var taskTitle = ""
    @State private var notes = ""
    @State private var selectedDate = Date()
    @State private var selectedTime = Date()
    @State private var showingDatePicker = false
    @State private var selectedList: EKCalendar?
    @FocusState private var isTitleFocused: Bool
    
    private let timeButtons: [(String, () -> Date)] = [
        ("Now", { Date() }),
        ("Today", { Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date() }),
        ("Tmw", {
            Calendar.current.date(
                bySettingHour: 9,
                minute: 0,
                second: 0,
                of: Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
            ) ?? Date()
        }),
        ("+1h", { Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date() }),
        ("+6h", { Calendar.current.date(byAdding: .hour, value: 6, to: Date()) ?? Date() })
    ]
    
    private let hourButtons = [
        ("9am", 9), ("12pm", 12), ("6pm", 18),
        ("+1h", 1), ("+6h", 6)  // Removed "+24h" from here
    ]
    
    // Add this new property
    let preloadedLists: [EKCalendar]
    
    init(preloadedLists: [EKCalendar] = []) {
        self.preloadedLists = preloadedLists
        if let defaultList = preloadedLists.first {
            _selectedList = State(initialValue: defaultList)
        }
    }
    
    var body: some View {
        NavigationStack {
            Form {
                VStack(spacing: 12) {
                    // Title and Due Date Row
                    HStack(spacing: 12) {
                        TextField("Task title...", text: $taskTitle)
                            .focused($isTitleFocused)
                            .onSubmit(createTaskIfValid)
                            .textFieldStyle(.roundedBorder)
                        
                        DueDateView(date: selectedDate, time: selectedTime)
                    }
                    
                    // Notes and List Row
                    HStack(spacing: 12) {
                        TextField("Add a note...", text: $notes)
                            .textFieldStyle(.roundedBorder)
                        
                        ListPickerButton(
                            selectedList: selectedList,
                            onCycle: cycleToNextList
                        )
                    }
                    
                    // Quick Actions
                    QuickActionButtons(
                        timeButtons: timeButtons,
                        hourButtons: hourButtons,
                        showingDatePicker: $showingDatePicker,
                        selectedDate: $selectedDate,
                        selectedTime: $selectedTime
                    )
                    
                    if showingDatePicker {
                        DatePicker("", selection: $selectedDate, displayedComponents: [.date])
                            .datePickerStyle(.graphical)
                    }
                }
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                .listRowBackground(Color.clear)
            }
            .scrollContentBackground(.hidden)
            .scrollIndicators(.hidden)
            .background(Color.customBackground)
        }
        .onAppear {
            isTitleFocused = true
            selectedList = eventStore.defaultCalendarForNewReminders()
        }
    }
    
    private func createTaskIfValid() {
        guard !taskTitle.isEmpty && selectedList != nil else { return }
        createTask()
    }
    
    private func cycleToNextList() {
        guard !preloadedLists.isEmpty else { return }
        
        let nextIndex: Int
        if let currentList = selectedList,
           let currentIndex = preloadedLists.firstIndex(of: currentList) {
            nextIndex = (currentIndex + 1) % preloadedLists.count
        } else {
            nextIndex = 0
        }
        
        selectedList = preloadedLists[nextIndex]
        HapticManager.selection()
    }
    
    private func createTask() {
        guard let calendar = selectedList else { return }
        
        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = taskTitle
        reminder.notes = notes
        reminder.calendar = calendar
        reminder.dueDateComponents = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: selectedDate.mergingTime(selectedTime)
        )
        
        do {
            try eventStore.save(reminder, commit: true)
            HapticManager.selection()
            Task {
                await updateApplicationBadge(eventStore: eventStore)
            }
            dismiss()
        } catch {
            print("Error saving reminder: \(error)")
        }
    }
}

// Helper Views
private struct DueDateView: View {
    let date: Date
    let time: Date
    
    var body: some View {
        Text(formatDueDateTime())
            .font(.caption)
            .foregroundStyle(Color.currentAccent)
            .padding(.vertical, 2)
            .multilineTextAlignment(.trailing)
    }
    
    private func formatDueDateTime() -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "E, d'\(daySuffix(for: date))' MMM"
        
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "ha"
        timeFormatter.amSymbol = "am"
        timeFormatter.pmSymbol = "pm"
        
        // Combine time and date in one row
        return "\(timeFormatter.string(from: time).lowercased()) • \(dateFormatter.string(from: date))"
    }
    
    private func daySuffix(for date: Date) -> String {
        let day = Calendar.current.component(.day, from: date)
        switch day {
        case 1, 21, 31: return "st"
        case 2, 22: return "nd"
        case 3, 23: return "rd"
        default: return "th"
        }
    }
}

private struct ListPickerButton: View {
    let selectedList: EKCalendar?
    let onCycle: () -> Void
    
    var body: some View {
        if let list = selectedList {
            Button(action: onCycle) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color(cgColor: list.cgColor))
                        .frame(width: 12, height: 12)
                    Text(list.title)
                        .foregroundStyle(.primary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
        }
    }
}

private struct QuickActionButtons: View {
    let timeButtons: [(String, () -> Date)]
    let hourButtons: [(String, Int)]
    @Binding var showingDatePicker: Bool
    @Binding var selectedDate: Date
    @Binding var selectedTime: Date
    
    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                ForEach(timeButtons, id: \.0) { title, action in
                    QuickButton(title: title) {
                        if title == "+1D" {
                            // Add one day to current selected date
                            let newDate = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate) ?? Date()
                            selectedDate = newDate
                            selectedTime = newDate
                        } else {
                            let newDate = action()
                            selectedDate = newDate
                            selectedTime = newDate
                        }
                        HapticManager.selection()
                    }
                }
                
                QuickButton(title: "•••") {
                    showingDatePicker.toggle()
                    HapticManager.selection()
                }
            }
            
            HStack(spacing: 8) {
                ForEach(hourButtons, id: \.0) { title, hours in
                    QuickButton(title: title) {
                        if title.hasPrefix("+") {
                            // Add hours to current selected date/time
                            let newDate = Calendar.current.date(byAdding: .hour, value: hours, to: selectedDate) ?? Date()
                            selectedDate = newDate
                            selectedTime = newDate
                        } else {
                            // Set specific hour
                            selectedTime = Calendar.current.date(bySettingHour: hours, minute: 0, second: 0, of: selectedDate) ?? Date()
                        }
                        HapticManager.selection()
                    }
                }
            }
        }
    }
}

private struct QuickButton: View {
    let title: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption)  // Make text smaller
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(0)  // Remove all padding
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
    }
}

// Date Extension
extension Date {
    func mergingTime(_ time: Date) -> Date {
        let calendar = Calendar.current
        let timeComponents = calendar.dateComponents([.hour, .minute], from: time)
        return calendar.date(bySettingHour: timeComponents.hour ?? 0,
                           minute: timeComponents.minute ?? 0,
                           second: 0, of: self) ?? self
    }
}

struct BlurView: UIViewRepresentable {
    func makeUIView(context: Context) -> UIVisualEffectView {
        // Using regular blur effect for Gaussian blur
        UIVisualEffectView(effect: UIBlurEffect(style: .regular))
    }
    
    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {}
}

// Update the modifier to use a transparent background
extension View {
    func withBottomBlurArea() -> some View {
        self.overlay(
            GeometryReader { geometry in
                VStack {
                    Spacer()
                    BlurView()
                        .frame(height: 100)
                        .allowsHitTesting(true)
                        .background(Color.clear)
                        .opacity(0)
                }
                .ignoresSafeArea()
            }
        )
    }
}

// Add a new color extension for the background
extension Color {
    static let customBackground = Color(uiColor: UIColor { traitCollection in
        switch traitCollection.userInterfaceStyle {
        case .dark:
            return UIColor(white: 0.12, alpha: 1.0)
        default:
            return UIColor(white: 0.94, alpha: 1.0)
        }
    })
    
    static let sidebarBackground = Color(uiColor: UIColor { traitCollection in
        switch traitCollection.userInterfaceStyle {
        case .dark:
            return UIColor(white: 0.08, alpha: 1.0)  // Keep 8% white for dark mode
        default:
            return UIColor(white: 0.88, alpha: 1.0)  // Changed from 0.82 to 0.88 for light mode
        }
    })
    
    static let accentOrange = Color(red: 255/255, green: 98/255, blue: 0/255)
    static let softRed = Color(red: 255/255, green: 85/255, blue: 100/255)  // Add this line
    
    static let accentColors: [(name: String, color: Color)] = [
        ("International", Color(red: 255/255, green: 79/255, blue: 0/255)),
        ("Storm", Color(red: 66/255, green: 72/255, blue: 78/255)),       
        ("Ruby", Color(red: 178/255, green: 31/255, blue: 46/255)),       
        ("Plum", Color(red: 142/255, green: 69/255, blue: 133/255)),
        ("Sunflower", Color(red: 227/255, green: 181/255, blue: 30/255)), 
        ("Denim", Color(red: 68/255, green: 109/255, blue: 146/255)),  // Changed from Ocean to Denim and updated RGB values    
        ("Forest", Color(red: 47/255, green: 91/255, blue: 32/255)),      
        ("Teal", Color(red: 68/255, green: 136/255, blue: 132/255))       
    ]
    
    static var currentAccent: Color {
        let storedIndex = UserDefaults.standard.integer(forKey: "AccentColorIndex")
        return accentColors[storedIndex].color
    }
}

// Add this extension at the bottom of your file, after the Color extension
extension View {
    func customNavigationBarBackButtonTitle() -> some View {
        self.modifier(NavigationBarModifier())
    }
}

struct NavigationBarModifier: ViewModifier {
    init() {
        let appearance = UINavigationBarAppearance()
        let backButtonAppearance = UIBarButtonItemAppearance()
        backButtonAppearance.normal.titleTextAttributes = [.foregroundColor: UIColor.secondaryLabel.withAlphaComponent(0.00)]
        appearance.backButtonAppearance = backButtonAppearance
        
        appearance.configureWithTransparentBackground()
        // Set the navigation bar background color to match our custom background
        appearance.backgroundColor = UIColor { traitCollection in
            switch traitCollection.userInterfaceStyle {
            case .dark:
                return UIColor(white: 0.12, alpha: 1.0)
            default:
                return UIColor(white: 0.94, alpha: 1.0)
            }
        }
        
        // Set the back indicator color to gray
        appearance.setBackIndicatorImage(
            UIImage(systemName: "chevron.left")?
                .withTintColor(.secondaryLabel, renderingMode: .alwaysOriginal),
            transitionMaskImage: UIImage(systemName: "chevron.left")?
                .withTintColor(.secondaryLabel, renderingMode: .alwaysOriginal)
        )
        
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        
        // Set the tint color for the back button
        UINavigationBar.appearance().tintColor = .secondaryLabel
    }
    
    func body(content: Content) -> some View {
        content
    }
}

// Update the custom toggle style
struct CircleToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button(action: { configuration.isOn.toggle() }) {
            Image(systemName: configuration.isOn ? "circle.inset.filled" : "circle")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.currentAccent)
                .font(.system(size: 20))
        }
    }
}

// Add this extension to handle notifications
extension UNUserNotificationCenter {
    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.badge, .alert, .sound]) { granted, error in
            if granted {
                print("Notification permission granted")
            } else if let error = error {
                print("Error requesting notification permission: \(error)")
            }
        }
    }
}

// Update the updateApplicationBadge function
func updateApplicationBadge(eventStore: EKEventStore) async {
    // Get the badge setting
    let showBadges = UserDefaults.standard.bool(forKey: "showBadges")
    
    // If badges are disabled, clear the badge and return
    if !showBadges {
        await MainActor.run {
            UNUserNotificationCenter.current().setBadgeCount(0) { error in
                if let error = error {
                    print("Error clearing badge count: \(error)")
                }
            }
        }
        return
    }
    
    do {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        
        // Get hidden lists from UserDefaults
        let hiddenListsData = UserDefaults.standard.data(forKey: "hiddenLists") ?? Data()
        let hiddenListIds = (try? JSONDecoder().decode(Set<String>.self, from: hiddenListsData)) ?? []
        
        // Filter out hidden calendars
        let visibleCalendars = eventStore.calendars(for: .reminder)
            .filter { !hiddenListIds.contains($0.calendarIdentifier) }
            
        var taskCount = 0
        
        for reminderCalendar in visibleCalendars {
            let predicate = eventStore.predicateForReminders(in: [reminderCalendar])
            let fetchedReminders = try await withCheckedThrowingContinuation { continuation in
                eventStore.fetchReminders(matching: predicate) { reminders in
                    if let reminders = reminders {
                        continuation.resume(returning: reminders)
                    } else {
                        continuation.resume(throwing: NSError(domain: "ReminderError", code: -1))
                    }
                }
            }
            
            let filteredCount = fetchedReminders.filter { reminder in
                guard let dueDate = reminder.dueDateComponents?.date else { return false }
                return dueDate >= today && 
                       dueDate < tomorrow && 
                       !reminder.isCompleted
            }.count
            
            taskCount += filteredCount
        }
        
        // Update the app badge
        await MainActor.run {
            UNUserNotificationCenter.current().setBadgeCount(taskCount) { error in
                if let error = error {
                    print("Error setting badge count: \(error)")
                }
            }
        }
        
    } catch {
        print("Error updating badge count: \(error)")
    }
}

// Replace the UniversalTaskComposerView with this simplified version:

struct UniversalTaskComposerView: View {
    @Environment(\.dismiss) private var dismiss
    let eventStore = EKEventStore()
    
    @State private var taskTitle = ""
    @State private var notes = ""
    @State private var selectedDate = Date()
    @State private var selectedTime = Date()
    @State private var showingDatePicker = false
    @State private var selectedList: EKCalendar?
    @FocusState private var isTitleFocused: Bool
    @State private var isPriority = false
    
    private let timeButtons: [(String, () -> Date)] = [
        ("Now", { Date() }),
        ("Today", { Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date() }),
        ("Tmw", {
            Calendar.current.date(
                bySettingHour: 9,
                minute: 0,
                second: 0,
                of: Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
            ) ?? Date()
        }),
        ("+1D", { Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date() })
    ]
    
    private let hourButtons = [
        ("9am", 9), ("12pm", 12), ("6pm", 18),
        ("+1h", 1), ("+6h", 6)
    ]
    
    let preloadedLists: [EKCalendar]
    
    init(preloadedLists: [EKCalendar] = []) {
        self.preloadedLists = preloadedLists
        if let defaultList = preloadedLists.first {
            _selectedList = State(initialValue: defaultList)
        }
    }
    
    var body: some View {
        NavigationStack {
            Form {
                VStack(spacing: 4) {
                    // Title and Due Date Row
                    HStack(spacing: 12) {
                        TextField("Task title...", text: $taskTitle)
                            .focused($isTitleFocused)
                            .onSubmit(createTaskIfValid)
                            .font(.title3.bold())
                            .textFieldStyle(.plain)
                        
                        DueDateView(date: selectedDate, time: selectedTime)
                    }
                    .padding(.bottom, 12)  // Changed from 8 to 12
                    
                    // Notes Row with Priority Button and List Button
                    HStack(spacing: 12) {
                        TextField("Add a note...", text: $notes)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .textFieldStyle(.plain)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .layoutPriority(1)  // Give priority to notes field
                        
                        Button(action: {
                            isPriority.toggle()
                            HapticManager.selection()
                        }) {
                            Image(systemName: isPriority ? "flag.fill" : "flag")
                                .font(.caption)
                                .foregroundStyle(isPriority ? Color.currentAccent : .secondary)
                                .frame(maxWidth: .infinity)
                                .padding(0)
                        }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                        .frame(width: UIScreen.main.bounds.width * 0.10)  // 10% of screen width
                        
                        Button(action: {
                            // Action for list selection
                            HapticManager.selection()
                        }) {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(Color(cgColor: selectedList?.cgColor ?? .init(gray: 0.5, alpha: 1.0)))
                                    .frame(width: 8, height: 8)
                                Text(selectedList?.title ?? "List")
                                    .lineLimit(1)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(0)
                        }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                        .frame(width: UIScreen.main.bounds.width * 0.20)  // 20% of screen width
                    }
                    
                    // Quick Actions
                    QuickActionButtons(
                        timeButtons: timeButtons,
                        hourButtons: hourButtons,
                        showingDatePicker: $showingDatePicker,
                        selectedDate: $selectedDate,
                        selectedTime: $selectedTime
                    )
                    .padding(.top, 8)
                }
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                .listRowBackground(Color.clear)
            }
            .scrollContentBackground(.hidden)
            .scrollIndicators(.hidden)
            .background(Color.customBackground)
        }
        .sheet(isPresented: $showingDatePicker) {
            NavigationStack {
                DatePicker("", selection: $selectedDate, displayedComponents: [.date])
                    .datePickerStyle(.graphical)
                    .padding()
                    .navigationTitle("Select Date")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") {
                                showingDatePicker = false
                            }
                        }
                    }
            }
            .presentationDetents([.height(400)])
            .presentationDragIndicator(.visible)
        }
        .onAppear {
            isTitleFocused = true
            selectedList = eventStore.defaultCalendarForNewReminders()
        }
    }
    
    private func createTaskIfValid() {
        guard !taskTitle.isEmpty && selectedList != nil else { return }
        createTask()
    }
    
    private func createTask() {
        guard let calendar = selectedList else { return }
        
        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = taskTitle
        reminder.notes = notes
        reminder.calendar = calendar
        reminder.priority = isPriority ? 1 : 0  // Set priority (1 for high, 0 for none)
        reminder.dueDateComponents = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: selectedDate.mergingTime(selectedTime)
        )
        
        do {
            try eventStore.save(reminder, commit: true)
            HapticManager.selection()
            Task {
                await updateApplicationBadge(eventStore: eventStore)
            }
            dismiss()
        } catch {
            print("Error saving reminder: \(error)")
        }
    }
}

#Preview {
    ContentView()
}
