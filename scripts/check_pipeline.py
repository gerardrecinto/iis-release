"""Structure check for the Azure DevOps pipeline and template. Exits non-zero on any problem."""
import sys
import yaml

main = yaml.safe_load(open("pipelines/azure-pipelines.yml"))
tmpl = yaml.safe_load(open("pipelines/templates/deploy-iis.yml"))
errors = []

stages = [s for s in main["stages"] if "stage" in s]
uses = [s for s in main["stages"] if "template" in s]
if not stages or stages[0]["stage"] != "Build":
    errors.append("first stage must be Build")
envs = [u["parameters"]["environment"] for u in uses]
if envs != ["dev", "staging", "prod"]:
    errors.append(f"environments must be dev, staging, prod in order, got {envs}")
for prev, u in zip(["Build", "Deploy_dev", "Deploy_staging"], uses):
    if u["parameters"].get("dependsOn") != [prev]:
        errors.append(f"{u['parameters']['environment']} must depend on {prev}")
declared = {p["name"] for p in tmpl["parameters"]}
for u in uses:
    unknown = set(u["parameters"]) - declared
    if unknown:
        errors.append(f"template does not declare {sorted(unknown)}")
job = tmpl["stages"][0]["jobs"][0]
if "environment" not in job:
    errors.append("deploy job must target an environment so approvals apply")

if errors:
    print("\n".join(errors))
    sys.exit(1)
print("pipeline ok:", ", ".join(envs))
