# Phone integration — 11 November 2026

ListPhoneVehicles(source,cursor) and GetPhoneVehicleLocation(source,assetId) are server exports restricted to h4nr-phone. They reuse ownership/session and garage state rules; no remote mutation is granted.

Caller, session and ownership/duty checks are covered by offline tests. Real GTA
acceptance and coordinated resource restarts remain open. No live restart was
performed in this session.
