# Deploy runbook — single-host on AWS

This is [cheap-deploy.md](cheap-deploy.md) (one box, all six Kamal roles
co-located) translated to concrete AWS services. Read that first for the *why*;
this is the *how* on AWS.

**Target:** one EC2 instance running web + job + postgres + routing + geocoder +
tiles on the private Docker network, image pulled from ECR, TLS via the Kamal
proxy, DNS in Route 53, backups to S3. Iowa launch region.

> AWS is **not** the cheapest host for this shape — a comparable box on
> Hetzner/DO is roughly half the EC2 on-demand price. Pick AWS for ecosystem
> reasons (you're already there, IAM/S3/Route 53 in one place), and cut cost with
> a Savings Plan (§11). Cost table at the end.

Anonymity is unchanged: the accessory ports bind to `127.0.0.1` (see
`deploy.yml`), so routing/geocoder/tiles are never exposed outside the box.
Don't open security-group rules for them.

---

## Mental model: this is your docker-compose stack, in production

You already run this whole system as containers locally with
[`infra/docker-compose.yml`](../../infra/docker-compose.yml). **Kamal on one EC2
box is the same thing, deployed.** Same images, same private network, same
co-located services — Kamal is to production what docker-compose is to your
laptop. It only swaps the dev-only pieces for production-appropriate ones:

| Local (`docker compose up`) | AWS (this runbook — `kamal deploy`) |
|---|---|
| `docker compose up` on your machine | `kamal deploy` to one EC2 instance |
| Services share the compose network | Same containers share the private Docker network |
| `postgres` / `routing` / `geocoder` / `tileserver` services | The **same images**, run as Kamal *accessories* (already in `deploy.yml`) |
| `backend` via `Dockerfile.dev`, source bind-mounted | prod `Dockerfile`, image baked & pushed to ECR — no source mount |
| `frontend` Vite dev server | built static assets served by the app |
| Plain HTTP on `localhost` | Kamal proxy terminates TLS (Let's Encrypt) on 443 |
| `docker compose down` / `up` | `kamal deploy` does a **zero-downtime** rolling swap; `kamal rollback` reverts |

So nothing about the *containers* changes going to AWS — the topology you already
debug locally is the topology that runs in prod. What this runbook adds is just
the cloud scaffolding around that same container set: a VM to run them on (§1–4),
a registry to pull from (§5), a stable address + TLS (§3a, §6), and managed
backups (§9). If you can read the compose file, you can read `deploy.yml` — they
describe the same stack.

> Want it *even more literal* (raw `docker compose up` on the EC2 box instead of
> Kamal)? You can, but you'd hand-rebuild what `deploy.yml` already gives you — a
> production compose file (prod images, no bind mounts) plus a reverse proxy for
> TLS — and lose zero-downtime deploys and pinned-digest rollouts. Kamal is the
> better-managed version of exactly that idea, which is why it's the path here.

---

## 0. Before you start

Have these from [cheap-deploy.md](cheap-deploy.md) §3 ready: Rails `master.key`,
DB/Nominatim passwords, the deploy SSH keypair, and a built **geo release**
(`build-geo.yml`). Install the AWS CLI and `kamal`:

```bash
aws --version            # v2
aws configure            # access key with admin-ish perms for setup
gem install kamal -v "~> 2.0"
```

Pick a region close to Iowa users — `us-east-2` (Ohio) or `us-east-1` (N.
Virginia). Set it once so the commands below inherit it:

```bash
export AWS_REGION=us-east-2
export AWS_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
```

---

## 1. Choose the instance

Your image is built `amd64` (`builder.arch: amd64` in `deploy.yml`), so use an
**x86_64** instance — don't pick Graviton (ARM) unless you also switch the
builder to `arm64`.

| Option | vCPU / RAM | ~On-demand (us-east-2) | Notes |
|---|---|---|---|
| `c6i.xlarge` | 4 / 8 GiB | ~$0.17/hr (~$123/mo) | Clean match to the cheap-deploy spec. |
| `t3.xlarge` | 4 / 16 GiB | ~$0.166/hr (~$120/mo) | **Recommended.** Burstable + extra RAM gives the Nominatim import headroom. |
| `t3.large` | 2 / 8 GiB | ~$0.083/hr (~$60/mo) | Cheapest that runs it; tight during the import. |

**Recommendation:** `t3.xlarge`. The extra 8 GB absorbs the one-time Nominatim
first-boot import, which is the only real memory spike. Drop to `t3.large` later
if steady-state usage is low.

Storage: a **30–80 GB gp3 root EBS volume**. Postgres + Nominatim index + tiles +
the routing graph share it; start at 50 GB for Iowa and alert at 75% (§10).

---

## 2. Networking & access

### 2a. Key pair (for the EC2 admin login)

Import the **public** half of your deploy keypair so you can SSH in as `ubuntu`:

```bash
aws ec2 import-key-pair --key-name flckd-deploy \
  --public-key-material fileb://backend/kamal_deploy.pub
```

### 2b. Security group

Open only 22 / 80 / 443. **Lock SSH to your IP.** The accessories need no rules
(they're `127.0.0.1`-bound).

```bash
SG_ID=$(aws ec2 create-security-group --group-name flckd-sg \
  --description "flckd single-host" --query GroupId --output text)

MYIP=$(curl -fsS https://checkip.amazonaws.com)
aws ec2 authorize-security-group-ingress --group-id $SG_ID \
  --protocol tcp --port 22 --cidr ${MYIP}/32           # SSH — you only
aws ec2 authorize-security-group-ingress --group-id $SG_ID \
  --protocol tcp --port 80 --cidr 0.0.0.0/0            # HTTP (Let's Encrypt + redirect)
aws ec2 authorize-security-group-ingress --group-id $SG_ID \
  --protocol tcp --port 443 --cidr 0.0.0.0/0           # HTTPS
```

---

## 3. Launch the instance

Use the latest Ubuntu LTS AMI (SSM gives you the current ID without hunting):

```bash
AMI_ID=$(aws ssm get-parameter \
  --name /aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id \
  --query Parameter.Value --output text)

aws ec2 run-instances \
  --image-id $AMI_ID \
  --instance-type t3.xlarge \
  --key-name flckd-deploy \
  --security-group-ids $SG_ID \
  --block-device-mappings '[{"DeviceName":"/dev/sda1","Ebs":{"VolumeSize":50,"VolumeType":"gp3"}}]' \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=flckd}]' \
  --query 'Instances[0].InstanceId' --output text
```

Save the returned instance ID as `INSTANCE_ID`.

### 3a. Stable address (Elastic IP)

DNS and Let's Encrypt need an address that survives reboots:

```bash
ALLOC_ID=$(aws ec2 allocate-address --query AllocationId --output text)
aws ec2 associate-address --instance-id $INSTANCE_ID --allocation-id $ALLOC_ID
EIP=$(aws ec2 describe-addresses --allocation-ids $ALLOC_ID \
  --query 'Addresses[0].PublicIp' --output text)
echo "Elastic IP: $EIP"
```

> Cost note: since 2024 AWS charges ~$0.005/hr (~$3.60/mo) for **every** public
> IPv4, even an attached one. Budget for it; it's unavoidable with a public box.

---

## 4. Prepare the host (Docker + deploy user)

Kamal drives Docker over SSH, so the host just needs Docker and an SSH-reachable
deploy user. SSH in as `ubuntu@$EIP` and:

```bash
# Docker
curl -fsSL https://get.docker.com | sh

# A 'deploy' user that can run Docker and reuses your deploy key
sudo adduser --disabled-password --gecos "" deploy
sudo usermod -aG docker deploy
sudo rsync -a --chown=deploy:deploy ~/.ssh/ /home/deploy/.ssh/
```

Kamal will connect as `deploy@$EIP`. (Locking down further — fail2ban, automatic
security updates — is good hygiene but out of scope here.)

---

## 5. Container registry (ECR)

Create one private repo for the app image:

```bash
aws ecr create-repository --repository-name flckd-backend \
  --query 'repository.repositoryUri' --output text
# => <ACCOUNT>.dkr.ecr.<region>.amazonaws.com/flckd-backend
```

### ⚠️ The ECR token gotcha

ECR has **no static password** — you authenticate with a token that **expires in
12 hours**. Kamal logs into the registry with whatever `KAMAL_REGISTRY_PASSWORD`
holds, so you must refresh it each deploy session. Generate it right before
deploying:

```bash
export KAMAL_REGISTRY_USERNAME=AWS
export KAMAL_REGISTRY_PASSWORD=$(aws ecr get-login-password --region $AWS_REGION)
```

`.kamal/secrets` can read these straight from the shell — set it to:

```bash
KAMAL_REGISTRY_USERNAME=$KAMAL_REGISTRY_USERNAME
KAMAL_REGISTRY_PASSWORD=$KAMAL_REGISTRY_PASSWORD
```

> Hands-off alternative: give the EC2 instance an IAM role with
> `AmazonEC2ContainerRegistryReadOnly` and install the **ECR docker credential
> helper** on the host so *pulls* need no token. You still need a fresh token to
> *push* from your laptop/CI. For occasional solo deploys, the 12-hour token is
> simpler — start there.

---

## 6. DNS (Route 53)

If your domain's zone is in Route 53, point the API name at the Elastic IP:

```bash
ZONE_ID=$(aws route53 list-hosted-zones-by-name \
  --dns-name flckd.example --query 'HostedZones[0].Id' --output text)

cat > /tmp/dns.json <<JSON
{"Changes":[{"Action":"UPSERT","ResourceRecordSet":{
  "Name":"api.flckd.example","Type":"A","TTL":300,
  "ResourceRecords":[{"Value":"$EIP"}]}}]}
JSON

aws route53 change-resource-record-sets --hosted-zone-id $ZONE_ID \
  --change-batch file:///tmp/dns.json
```

Wait for it to resolve (`dig api.flckd.example`) **before** `kamal setup` — the
Kamal proxy requests a Let's Encrypt cert on first boot and needs the name
pointing at the box. (A Route 53 hosted zone is $0.50/mo.)

---

## 7. Wire `deploy.yml` for AWS

In [`backend/config/deploy.yml`](../../backend/config/deploy.yml), fill the
placeholders — every host is the **same** Elastic IP:

```yaml
image: <ACCOUNT>.dkr.ecr.<region>.amazonaws.com/flckd-backend
registry:
  server: <ACCOUNT>.dkr.ecr.<region>.amazonaws.com
servers:
  web:    [ deploy@<EIP> ]
  job:
    hosts: [ deploy@<EIP> ]
    cmd: bin/jobs
proxy:
  host: api.flckd.example
accessories:           # all point at the same box
  postgres:  { host: deploy@<EIP>, ... }
  routing:   { host: deploy@<EIP>, ... }
  geocoder:  { host: deploy@<EIP>, ... }
  tiles:     { host: deploy@<EIP>, ... }
```

Leave the geo accessory **image digests pinned** and keep `app_port: 80`,
`WEB_CONCURRENCY: 2`, `SOLID_QUEUE_IN_PUMA: false` as shipped. Validate:

```bash
cd backend && kamal config        # no unresolved placeholders / secrets
```

---

## 8. Bring-up

Same sequence as [cheap-deploy.md](cheap-deploy.md) §4 — refresh the ECR token
first (§5):

```bash
export KAMAL_REGISTRY_PASSWORD=$(aws ecr get-login-password --region $AWS_REGION)

cd backend
kamal setup                                   # build → push to ECR → boot all roles + proxy/TLS
kamal app exec 'bin/rails db:prepare'         # schema (PostGIS included)
# Then run deploy-geo.yml with your geo release tag to load the graph/tiles.
```

Smoke-test per [cheap-deploy.md](cheap-deploy.md) §5 (health + a Des
Moines→Iowa City route + a geocode + tiles in the frontend).

---

## 9. Backups to S3

Postgres is the only irreplaceable state. Create a private bucket and an IAM
identity that can only write to it:

```bash
aws s3api create-bucket --bucket flckd-backups-$AWS_ACCOUNT \
  --region $AWS_REGION \
  --create-bucket-configuration LocationConstraint=$AWS_REGION
aws s3api put-bucket-versioning --bucket flckd-backups-$AWS_ACCOUNT \
  --versioning-configuration Status=Enabled
```

Then schedule a `pg_dump` from the host (cron or a Solid Queue job) that pipes to
`aws s3 cp - s3://…`. Follow the dump/restore procedure in
[backups.md](backups.md) and **test a restore once**. Give the uploader
least-privilege (`s3:PutObject` on that bucket only) via an IAM user or the
instance role — never the root keys.

---

## 10. Day-one essentials on AWS

- [ ] **CloudWatch disk alarm** at 75% — one EBS volume backs Postgres + Nominatim
      + tiles; a full disk takes everything down. (Needs the CloudWatch agent for
      disk metrics; EBS-level metrics alone won't show filesystem usage.)
- [ ] **EBS snapshot schedule** (Data Lifecycle Manager) as a cheap block-level
      backup *in addition to* the logical `pg_dump` — they cover different failures.
- [ ] **Don't rely on Spot** for this box — it's stateful and a reclaim is an
      outage. On-demand or a Savings Plan only.
- [ ] Rollback: `kamal rollback` swaps the app image instantly; **EBS/Postgres do
      not roll back** — a bad migration needs the §9 restore path.
- [ ] Confirm the SSH security-group rule is still your-IP-only after any change.

---

## 11. Cost (rough, us-east-2 on-demand)

| Item | ~Monthly |
|---|---|
| `t3.xlarge` (4 vCPU / 16 GB) | ~$120 |
| 50 GB gp3 EBS | ~$4 |
| Elastic IP (IPv4 charge) | ~$3.60 |
| Route 53 hosted zone | $0.50 |
| S3 backups (a few GB + snapshots) | a few $ |
| **Total** | **~$130/mo on-demand** |

**Cut it down:**
- **Compute Savings Plan** (1-yr, no upfront): ~40% off the instance → ~$72/mo.
- **`t3.large`** instead of xlarge once steady-state is known: roughly halves
  compute (tight during the Nominatim import — size up just for that, then down).
- **Reserved/Graviton**: Graviton (`t4g`/`c7g`) is ~20% cheaper but requires
  building `arm64` images (flip `builder.arch`). Worth it only if you commit.

---

## 12. Teardown (avoid surprise bills)

```bash
aws ec2 terminate-instances --instance-ids $INSTANCE_ID
aws ec2 release-address --allocation-id $ALLOC_ID        # unattached EIPs bill the most
aws ec2 delete-security-group --group-id $SG_ID
aws ecr delete-repository --repository-name flckd-backend --force
# Keep the S3 backup bucket + Route 53 zone unless you're truly done.
```

Snapshot or `pg_dump` first if there's any data you want to keep — termination
deletes the root EBS volume by default.
```
