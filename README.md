# Schedule DSLink

A DSLink for Scheduling Values.

**Note:** This version is currently a transition build from the previous implementation
to a new underlying engine and forward facing node tree. Little information will be documented
about the legacy interface, and hopefully in the future it will go away.

## Schedules

You may have multiple schedules and each schedule will operate independent of other schedules. However
within a schedule, there will only be, at most, one active event at a time.

To create a new schedule, use the `Add Schedule` action on the root node of this link. Note that
`Add Remote Schedule` and `Add Local Schedule` are part of the legacy interface and should not be used for
new schedules going forward.

Each schedule requires a unique name, and a default value. The default value is the value that will be provided
when there are no events actively occurring.

## Events

There is only one event type, however for convenience there are three ways of adding an event. Each of these can be 
found as actions on the **Events** node under your schedule.

### Add Event
The `Add Event` action is the easiest way to add a simple Event with separate Start and End date and times. If you have
an event that occurs only once, over a timerange of any size, this is the action to use. This action takes a `name`, a
`value` which will be produced by the schedule's `Current Value` when the event is active. It also optionally has an
`isSpecial` flag to indicate if this event should be treated as a [Special Event](#special-events), and as well a 
`priority` to indicate what [Priority](#priority) the event should have.

The `dateRange` of Add Event should be two dates in ISO8601 format separated by a `/`, or use the DateRange picker.
Times will use the server's local timezone. You can force UTC time by appending a `Z` to the end of the Timestamp.
 
For example: 
```
2020-04-30T17:00:00.000/2020-04-30T18:00:00.000
```

### Add Moment Event
The `Add Moment Event` is useful when you want to have an event that happens at a single moment in time. That is, rather
than a time range, it triggers and ends at one specific moment. As with all Events, this action takes a `name` and a
`value`. It also has the same `isSpecial` and `priority` values as referenced above.

The `dateTime` value may be a singe ISO8601 format string or if using the DateTime Picker, it will accept a time range
string of `<TimeStamp>/<TimeStamp>`, however only the first TimeStamp (that before the `/`) will be used and the
remaining will be ignored and discarded.

**Note:** If you use a Moment (or the same start and end times for an event), you may need to adjust your `QOS` settings
for any subscriptions on the `Current Value`, otherwise the value may be delivered as a merged value.

### Add Recurring Event
The `Add Recurring Event` action is the most powerful way of adding an event. Using this action we can create an event
which will automatically repeat itself (or not). Similar to above, this action requires a `name` and `value`. It also
has parameters for `isSpecial` and `priority`.

Unlike the others, this action takes two different ranges. <br>
The first is the `dateRange` which indicates the Start and End dates of the event. No events will happen past the end
value of the `dateRange` including the time. If you want an event to happen during the last hour of the event ensure that
the end value includes that timestamp as well.
The Second is the `timeRange` which is used to indicate the *active time* of the event. This is the period of time that
will reoccur throughout the specified `dateRange`, based on the Frequency selection.

`frequency` may be one of the following:

Frequency | Definition
----------|-----------
Single | Does not repeat.
Hourly | Repeats once every hour. TimeRange must be less than 1 hour in duration
Daily | Repeats once every day. TimeRange must be less than 24 hours. (Tries to happen at the same time of day so this may take place 23 or 25 hours after the last event if daylight savings changes between instances)
Weekly | Repeats once every week. TimeRange must be less than 7 days.
Monthly | Repeats once every month. TimeRange must be less than 28 days.
Yearly | Repeats once every year. TimeRange must be less than 365 days.

Examples:

1. If you want an event that happens once every hour on a single day (Starting at 8am and ending at 5pm)
    * `dateRange` = `2020-04-12T8:00:00.000/2020-04-12T17:00:00.000`
    * `timeRange` = `2020-04-12T8:00:00.000/2020-04-12T8:10:00.000` (note how this is only 10 minutes)
    * `frequency` = `Hourly`
    * Note that the last event is at 16:10 (4:10pm) otherwise we would surpass the time of the End date. 
2. An event happening hourly on the 15's for 15 minutes.
    * `dateRange` = `2020-04-01T00:15:00.000/2020-04-30T23:30:00.000`
    * `timeRange` = `2020-04-01T00:15:00.000/2020-04-1T00:30:00.000`
    * `frequency` = `Hourly`
    * For clarity note how the dateRange start time is 12:15am and end time is 11:30pm.
3. A daily event happening at 12pm - 1pm for the month of April.
    * `dateRange` = `2020-04-01T12:00:00.000/2020-04-30T13:00:00.000`
    * `timeRange` = `2020-04-01T12:00:00.000/2020-04-01T13:00:00.000`
    * `frequency` = `Daily`
4. A weekly event from Monday 8am - Friday 5pm each week (note: This is not daily, so it is one event that takes place overnight as well)
    * `dateRange` = `2020-03-30T08:00:00.000/2020-05-01T17:00:00.000`
    * `timeRange` = `2020-03-30T08:00:00.000/2020-04-03T17:00:00.000`
    * `frequency` = `Weekly`
    
Currently, it is not possible to have multiple stacked Timeframes. That is, you cannot currently have
an event that is both hourly and daily. So you cannot create a single event that takes place only 8-5 on Monday - Friday
for each week. This will need to be separated into multiple events (such as 5 weekly events).

## Special Events

Special Events are the same as a standard event. However, a special event has one additional property, in that it blocks
other events from happening on that day, regardless of if the times overlap. Thus if you have an event scheduled for
8 o'clock PM, and a special event is added from noon until one PM on that day, the 8 o'clock
event will not fire on that day.

If you have a week-long event, from Sunday to Saturday inclusive, if you add a moment special event on Wednesday,
then the regular event will take place from Sunday - Tuesday at 11:59:59pm, and resume again Thursday at midnight.

## Priority

Each event may have a priority. By default an event has a priority `0` which indicates signifies _no priority specified_
Following that: `1` is considered the highest priority and `9` is considered the lowest priority. A special event will
always take precedence over a priority 1, even if the special event has a priority of 9. However special events of
different priorities should follow expected behaviours.

## Import/Export

The export action on schedules will provide a JSON serialized representation of the schedule and its associated events.

Import will attempt to add the JSON string as a schedule. If a schedule exists by that name, it will attempt to update
that schedule instead. If the schedule does not exist, or you supply an alternative name, it will add as either a new
schedule or update the alternative name provided.
By default, the update will __not__ overwrite any existing events (as matched by Event ID). When overwrite is false,
any conflicts will be discarded and if the defaultValue has changed, it will not be updated. Only new events will be 
added. If overwrite is set to true, the defaultValue will be updated and any events with a matching ID will be 
overwritten with the imported version.