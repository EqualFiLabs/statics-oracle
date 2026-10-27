# Deterministic execution selection

All submitted reports are authenticated and validated. A bounded scan considers
every inclusive signed interval, regardless of array ordering or window width.
The executing chain timestamp minus the reviewed market delay selects the window.
The caller supplies neither a reference timestamp nor an authoritative price.

No price, report or global observation watermark is persisted. One consumer's
execution does not consume another consumer's window. Repeated matching entries
fail the unique-match rule; repeated nonmatching entries cannot change price but
count toward the immutable bundle bound. There is no additional duplicate pass.
