# Deterministic execution selection

All submitted reports are authenticated and validated. A bounded scan considers
every inclusive signed interval, regardless of array ordering or window width.
The executing chain timestamp minus the reviewed market delay selects the window.
The caller supplies neither a reference timestamp nor an authoritative price.
