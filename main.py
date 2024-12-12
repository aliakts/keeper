from google.cloud import compute_v1
import functions_framework
import json
import logging
from datetime import datetime
import time

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def check_and_restart_spots(project_id: str, zone: str):
    client_options = {"quota_project_id": project_id}
    instances_client = compute_v1.InstancesClient(client_options=client_options)
    
    logger.info(f"Initializing spot VM maintenance check [project={project_id}] [zone={zone}]")
    
    request = compute_v1.ListInstancesRequest(
        project=project_id,
        zone=zone
    )
    
    results = []
    try:
        instances = list(instances_client.list(request=request))
        spot_instances = [
            instance for instance in instances 
            if instance.scheduling.provisioning_model == "SPOT"
        ]
        
        logger.info(f"Found {len(spot_instances)} spot VMs")
        
        for instance in spot_instances:
            if instance.labels and instance.labels.get('exclude_from_keeper') == 'true':
                logger.info(f"VM instance [{instance.name}] excluded from keeper, skipping...")
                continue

            if instance.status == "TERMINATED":
                logger.info(f"VM instance [{instance.name}] was preempted, attempting to bring back online...")
                start_time = time.time()
                try:
                    restart_request = compute_v1.StartInstanceRequest(
                        project=project_id,
                        zone=zone,
                        instance=instance.name
                    )
                    operation = instances_client.start(request=restart_request)
                    operation.result()
                    
                    elapsed_time = time.time() - start_time
                    success_msg = f"VM instance [{instance.name}] is back online (took {elapsed_time:.2f} seconds)"
                    logger.info(success_msg)
                    results.append(success_msg)
                    
                except Exception as e:
                    error_msg = f"Error bringing VM instance [{instance.name}] back online: {str(e)}"
                    logger.error(error_msg)
                    results.append(error_msg)
            elif instance.status == "STOPPING":
                logger.info(f"VM instance [{instance.name}] is in stopping state, waiting for full preemption before taking action")
            else:
                status_msg = f"VM instance [{instance.name}] is {instance.status.lower()}, no action needed"
                logger.info(status_msg)
                results.append(status_msg)
    
    except Exception as e:
        error_msg = f"Error processing request: {str(e)}"
        logger.error(error_msg)
        results.append(error_msg)
    
    return results

@functions_framework.http
def spot_vm_service(request):
    """HTTP Cloud Function.
    Args:
        request (flask.Request): The request object.
        <https://flask.palletsprojects.com/en/1.1.x/api/#incoming-request-data>
    Returns:
        The response text, or any set of values that can be turned into a Response object.
        <https://flask.palletsprojects.com/en/1.1.x/api/#flask.make_response>
    """
    request_json = request.get_json(silent=True)
    request_args = request.args

    project_id = None
    zone = None

    if request_json and "project_id" in request_json:
        project_id = request_json["project_id"]
        zone = request_json.get("zone")
    elif request_args and "project_id" in request_args:
        project_id = request_args["project_id"]
        zone = request_args.get("zone")
    
    if not project_id:
        error_msg = "Missing required parameter: project_id"
        logger.error(error_msg)
        return json.dumps({"error": error_msg}), 400
    
    if not zone:
        error_msg = "Missing required parameter: zone"
        logger.error(error_msg)
        return json.dumps({"error": error_msg}), 400

    try:
        results = check_and_restart_spots(project_id, zone)
        return json.dumps({"results": results})
    except Exception as e:
        error_msg = f"Error processing request: {str(e)}"
        logger.error(error_msg)
        return json.dumps({"error": error_msg}), 500