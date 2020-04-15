# Schedule DSLink

A DSLink for Scheduling Values.

## Schedules

## Events

## Special Events

Special Events are the same as a standard event. However, a special event has one additional property, in that it blocks
other events from happening on that day, regardless of if the times overlap. Thus if you have an event scheduled for
8 o'clock PM, and a special event is added from noon until one PM on that day, the 8 o'clock
event will not fire on that day.

If you have a week-long event, from Sunday to Saturday inclusive, if you add a 1-minute special event on Wednesday,
then the regular event will take place from Sunday - Tuesday at 11:59:59pm, and resume again Thursday at midnight.