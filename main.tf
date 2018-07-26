# Configure Docker provider and connect to the local Docker socket
provider "docker" {
  host = "unix:///var/run/docker.sock"
}

resource "docker_container" "varnish" {
  count = 4
  image = "${docker_image.varnish_4_1.latest}"
  name  = "node${count.index + 1}"
  restart = "always"
  volumes {
    container_path = "/etc/varnish/default.vcl"
    host_path = "/Users/inhdddd/Documents/Docker/varnish/default.vcl"
    read_only = true
  }
  env = [ "VARNISHD_PARAMS=-i node${count.index + 1}" ]
  networks = [ "${docker_network.test.name}" ]
}

resource "docker_container" "nginx" {
  count = 2
  image = "${docker_image.nginx.latest}"
  name  = "nginx${format("%02d",count.index + 1)}"
  restart = "always"
  volumes {
    container_path = "/etc/nginx/conf.d/default.conf"
    host_path = "/Users/inhdddd/Documents/Docker/nginx/default.conf"
    read_only = true
  }
  networks = [ "${docker_network.test.name}" ]
}

resource "docker_image" "varnish_4_1" {
  name = "million12/varnish:latest"
}

resource "docker_image" "nginx" {
  name = "nginx:latest"
}

resource "docker_network" "test" {
  name = "example.com"
}