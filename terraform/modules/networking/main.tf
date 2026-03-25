# ── VPC ─────────────────────────────────────────────────────────────────────

resource "google_compute_network" "rag_vpc" {
  name                    = "rag-vpc-${var.environment}"
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
  project                 = var.project_id
}

# ── Subnet ───────────────────────────────────────────────────────────────────

resource "google_compute_subnetwork" "rag_subnet" {
  name                     = "rag-subnet-${var.environment}"
  network                  = google_compute_network.rag_vpc.id
  region                   = var.region
  ip_cidr_range            = var.vpc_cidr
  project                  = var.project_id
  private_ip_google_access = true # Required for Cloud Run → Google APIs without public IP

  log_config {
    aggregation_interval = "INTERVAL_5_SEC"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

# ── Cloud Router (required by Cloud NAT) ─────────────────────────────────────

resource "google_compute_router" "rag_router" {
  name    = "rag-router-${var.environment}"
  network = google_compute_network.rag_vpc.id
  region  = var.region
  project = var.project_id
}

# ── Cloud NAT ────────────────────────────────────────────────────────────────
# Allows VPC-internal Cloud Run services to reach the internet (e.g. PyPI)
# without assigning public IPs.

resource "google_compute_router_nat" "rag_nat" {
  name                               = "rag-nat-${var.environment}"
  router                             = google_compute_router.rag_router.name
  region                             = var.region
  project                            = var.project_id
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# ── Serverless VPC Access Connector ──────────────────────────────────────────
# Allows Cloud Run services to reach VPC-internal resources.
# Requires a dedicated /28 CIDR that must not overlap any existing subnet.

resource "google_vpc_access_connector" "rag_connector" {
  provider = google-beta

  name          = "rag-connector-${var.environment}"
  region        = var.region
  project       = var.project_id
  network       = google_compute_network.rag_vpc.name
  ip_cidr_range = var.vpc_connector_cidr

  min_instances  = 2
  max_instances  = 10
  max_throughput = 1000
  machine_type   = "e2-micro"
}

# ── Firewall: deny all ingress (default-deny posture) ────────────────────────

resource "google_compute_firewall" "deny_all_ingress" {
  name      = "rag-deny-all-ingress-${var.environment}"
  network   = google_compute_network.rag_vpc.name
  project   = var.project_id
  direction = "INGRESS"
  priority  = 65534

  deny {
    protocol = "all"
  }

  source_ranges = ["0.0.0.0/0"]
}

# ── Firewall: allow internal traffic within the VPC ───────────────────────────

resource "google_compute_firewall" "allow_internal" {
  name      = "rag-allow-internal-${var.environment}"
  network   = google_compute_network.rag_vpc.name
  project   = var.project_id
  direction = "INGRESS"
  priority  = 1000

  allow {
    protocol = "tcp"
  }

  allow {
    protocol = "udp"
  }

  allow {
    protocol = "icmp"
  }

  source_ranges = [var.vpc_cidr, var.vpc_connector_cidr]
}

# ── Firewall: allow health checks from Google probers ────────────────────────

resource "google_compute_firewall" "allow_health_checks" {
  name      = "rag-allow-health-checks-${var.environment}"
  network   = google_compute_network.rag_vpc.name
  project   = var.project_id
  direction = "INGRESS"
  priority  = 1000

  allow {
    protocol = "tcp"
  }

  # Google Cloud health check prober ranges
  source_ranges = ["35.191.0.0/16", "130.211.0.0/22"]
}

# ── Private Service Access (VPC Peering for Vertex AI Vector Search) ───────
# Vertex AI index endpoints with private networking require a peering
# connection to Google's servicenetworking VPC.

resource "google_compute_global_address" "private_service_range" {
  name          = "rag-private-service-range-${var.environment}"
  project       = var.project_id
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.rag_vpc.id
}

resource "google_service_networking_connection" "private_service_access" {
  network                 = google_compute_network.rag_vpc.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_service_range.name]
}
