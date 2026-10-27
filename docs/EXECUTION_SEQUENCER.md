# Execution sequencer boundary

The execution adapter reads the existing availability feed. NAV, the availability
feed, L1 reporter and observer implementation are unchanged. Health is evaluated
once per request with the existing zero-answer, nonzero/nonfuture recovery start
and strictly elapsed grace semantics. Feed lease expiry is represented by the
feed's unhealthy answer. Malformed data and feed failure reject execution.

This signal attests to liveness/progress, not independent timestamp honesty.
Execution reference time still relies on the chain timestamp.
