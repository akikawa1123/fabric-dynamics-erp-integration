import datetime
import json
import logging
import urllib.error
import urllib.request

import fabric.functions as fn

udf = fn.UserDataFunctions()


@udf.function()
def triggerQualityIncident(
    logicAppUrl: str,
    plantId: str = "JP-NAGOYA-01",
    lineId: str = "LINE-A",
    stationId: str = "ST-07-PRESS",
    productNumber: str = "CRCA",
    lotId: str = "LOT-CRCA-UNKNOWN",
    observedValue: str = "0",
    thresholdValue: str = "50",
    metricName: str = "torque_nm",
    unit: str = "Nm",
    dashboardUrl: str = "",
) -> dict:
    """Post an Activator alert payload to the Logic Apps incident ingress endpoint.

    Parameter names use camelCase because Fabric User Data Functions require it.
    The Logic App callback URL is a secret-like SAS URL; pass it from the
    Activator action parameter and do not commit it to source control.
    """

    payload = {
        "activationTime": datetime.datetime.utcnow().replace(microsecond=0).isoformat() + "Z",
        "plantId": plantId,
        "lineId": lineId,
        "stationId": stationId,
        "productNumber": productNumber,
        "lotId": lotId,
        "metricName": metricName,
        "observedValue": observedValue,
        "thresholdValue": thresholdValue,
        "unit": unit,
        "dashboardUrl": dashboardUrl,
    }
    request = urllib.request.Request(
        logicAppUrl,
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )

    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            response_text = response.read().decode("utf-8")
            logging.info("Logic App response: %s", response_text)
            return {
                "ok": True,
                "status": response.status,
                "requestPayload": payload,
                "logicAppResponse": json.loads(response_text) if response_text else {},
            }
    except urllib.error.HTTPError as ex:
        error_body = ex.read().decode("utf-8", errors="replace")
        logging.error("Logic App HTTPError %s: %s", ex.code, error_body)
        return {
            "ok": False,
            "status": ex.code,
            "requestPayload": payload,
            "error": error_body,
        }
    except Exception as ex:  # Surface the error to Activator; do not fabricate a success.
        logging.exception("Logic App invocation failed")
        return {"ok": False, "requestPayload": payload, "error": str(ex)}
