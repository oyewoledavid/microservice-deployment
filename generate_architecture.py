#!/usr/bin/env python3
"""
Improved Architecture diagram generator using diagrams library
Run: pip install diagrams
"""

from diagrams import Diagram, Cluster, Edge
from diagrams.aws.compute import EKS, EC2
from diagrams.aws.network import ALB, VPC, Route53
from diagrams.aws.security import CertificateManager
from diagrams.k8s.compute import Pod, Deployment
from diagrams.k8s.network import Service, Ingress
from diagrams.onprem.database import MongoDB, MySQL
from diagrams.onprem.inmemory import Redis
from diagrams.onprem.queue import RabbitMQ
from diagrams.onprem.monitoring import Prometheus, Grafana
from diagrams.onprem.client import Users

def create_architecture_diagram():
    # set show=True to open the image after generation
    with Diagram("Sock Shop Microservices Architecture (improved)", show=False, direction="TB"):

        # External users
        users = Users("Users")

        # AWS Cloud boundary
        with Cluster("AWS Cloud"):
            # DNS and SSL
            route53 = Route53("Route53\nsock.blessedc.org\n(Managed by ExternalDNS)")
            acm = CertificateManager("ACM Wildcard\n*.sock.blessedc.org\n(+ sock.blessedc.org SAN)")

            # VPC and EKS boundary
            with Cluster("VPC (Terraform-managed)"):
                alb = ALB("Application\nLoad Balancer\n(ALB - TLS Termination)")

                # IAM / IRSA reminder (visual note)
                iam_note = EC2("IRSA roles\n(alb-controller, external-dns)")

                # EKS Cluster and internal layout
                with Cluster("EKS Cluster"):
                    control_plane = EKS("EKS Control Plane")

                    # kube-system (controller) - show ALB controller & external-dns as deployments (IRSA-bound)
                    with Cluster("kube-system"):
                        alb_controller = Deployment("aws-load-balancer-controller\n(Deployment, IRSA)")
                        external_dns = Deployment("external-dns\n(Deployment, IRSA)")

                    # Worker nodes & namespaces
                    with Cluster("Worker Nodes"):
                        # sock-shop namespace
                        with Cluster("Namespace: sock-shop"):
                            with Cluster("Application Layer"):
                                ingress = Ingress("ALB Ingress (Ingress resources)")
                                frontend = Pod("Frontend\nService\n({{ .Release.Name }}-frontend)")

                            with Cluster("Business Logic"):
                                catalogue = Pod("Catalogue\nService")
                                carts = Pod("Carts\nService")
                                orders = Pod("Orders\nService")
                                payment = Pod("Payment\nService")
                                user = Pod("User\nService")
                                shipping = Pod("Shipping\nService")
                                queue_master = Pod("Queue\nMaster")

                            with Cluster("Data Layer"):
                                session_db = Redis("Session DB\n(Redis)")
                                carts_db = MongoDB("Carts DB")
                                user_db = MongoDB("User DB")
                                catalogue_db = MySQL("Catalogue DB\n(MySQL / RDS)")
                                orders_db = MongoDB("Orders DB")
                                rabbitmq = RabbitMQ("RabbitMQ")

                        # monitoring namespace
                        with Cluster("Namespace: monitoring"):
                            prometheus = Prometheus("Prometheus\n(Helm)")
                            grafana = Grafana("Grafana\n(Helm)")

        # Traffic flow and edges (explicit)
        users >> Edge(label="https://sock.blessedc.org") >> route53
        route53 >> Edge(label="A record -> ALB\n(created by ExternalDNS)") >> alb

        # show ExternalDNS updating Route53
        external_dns >> Edge(style="dashed", label="creates/updates DNS records") >> route53

        # ACM cert bound to ALB (DNS validated via Route53)
        acm >> Edge(style="dotted", color="green", label="DNS validated via Route53") >> alb

        # Controller and ALB -> Ingress
        alb_controller >> Edge(label="reconciles Ingress\ncreates target groups/listeners") >> alb
        alb >> Edge(label="routes traffic") >> ingress
        ingress >> frontend

        # Frontend -> backend services & session store
        frontend >> [catalogue, carts, orders, user, payment, shipping]
        frontend >> session_db

        # Service -> DB connections
        catalogue >> catalogue_db
        carts >> carts_db
        orders >> orders_db
        user >> user_db
        queue_master >> rabbitmq

        # Monitoring
        prometheus >> Edge(style="dashed", color="purple", label="scrapes") >> [frontend, catalogue, carts, orders, payment, user, shipping]
        grafana >> Edge(style="dashed", color="purple") >> prometheus

        # IRSA reminder visual
        iam_note >> Edge(style="dotted", label="IRSA for controller & external-dns") >> alb_controller
        iam_note >> Edge(style="dotted") >> external_dns

if __name__ == "__main__":
    create_architecture_diagram()
    print("Improved architecture diagram generated as 'sock_shop_microservices_architecture (improved).png'")
