If you already have a cluster created, and are familiar with running stateful applications and have used secrets as volumes you can probably skip to 
the [deployment section](#Deploy:)

### Why two example deployment files?
[plaintext-env-deployment.yaml](plaintext-env-deployment.yaml) has Environment variables, config, and secrets declared in one file.
This can be risky. Especially if you plan on storing your files in version control.


[deployment.yaml](deployment.yaml) separates environment variables, and credentials separated. You can even populate your 
[.conf file](#to-store-your-vpn-conf-file-as-a-secret-as-well) as a secret well. Not only does it help accidentally 
committing sensitive information, but will also make it easier to update values without redeploying. 
[reloader](https://github.com/stakater/Reloader) is a great tools for this. 

### Prerequisites

**Data / Config Volumes:**

Be sure your volume is [persistent](https://kubernetes.io/docs/concepts/storage/persistent-volumes/) 
otherwise your Deployment's configuration and torrent data will be lost.
Detailing the setup of how to persist data is not in the scope of these examples. 

I have Included are example [PersistentVolume](persistant-volume.yaml) and [PersistentVolumeClaim](pvc.yaml) files.
Deploying these files as is will result in loss of data.
These files are included to guide those wishing to populate a VPN Provider's .conf file through a secret. See the 
[secret](#vpn-conf-file-as-a-secret-into-your-deployment) section of the Notes below for more info.


**Credentials:**

For the sake simplicity, [creds.yaml](creds.yaml) is a straight forward example for creating a secret.

#####To store your VPN .conf file as a secret as well:

The example `deployment.yaml` secret file was populated using the
[--from-file](https://kubernetes.io/docs/tasks/inject-data-application/distribute-credentials-secure/#create-a-secret-directly-with-kubectl) arg.

to match the file named in the example, the command looks like this:

`kubectl create secret generic wireguard-conf --from-file=wg0.conf=wg.conf`

###Deploy:
**With configMaps and secrets**

Edit each respective file with the appropriate credentials and desired Environment Variables.

`kubectl apply -f config-map.yaml`

`kubectl apply -f creds.yaml`

`kubectl apply -f deployment.yaml`

`kubectl apply -f service.yaml`

**With all data (including credentials) defined plaintext in one yaml file:**

`kubectl apply -f plaintext-env-deployment.yaml`


### Notes:

####Networking:

**LAN_NETWORK settings**

For Pod to Pod communication, or using a reverse proxy like Traefik, 
the environment variable `LAN_NETWORK` needs to be set to your CNI's subnet (typically a 10.* CIDR) This subnet is 
created when first initializing the cluster. You should **NOT** your local network's subnet. Once your deploy is 
successful, you can verify the ENV variable was created successfully, from your master node:

`kubectl port-forward pod/$(kubectl get pods | grep arch-deluge | awk '{print $1}') 8112 & sleep 3 ; curl localhost:8112 
;  pkill -f "kubectl port-forward"` 

You should see the Deluge html generated from a curl command. 

**Connecting to the Pod from outside the cluster**

Depending on your network stack you will likely need to expose the pod to your local subnet. The example provided does
not expose your pod outside the cluster. There are various methods to create a service that has either an external 
IP address, proxy, or ingress. If you're new to Kubernetes 
 [docs](https://kubernetes.io/docs/tasks/administer-cluster/access-cluster-services/#ways-to-connect) are always a good
starting point. 

####Volumes:
Because this image adds configuration to `/conf` your `volumeMount` for `/conf` and `/conf/wireguard` should be 
attached to a single `volume`using a `subPath` under the same root folder.

`/data` can be mapped to a separate `PersistentVolumeClaim` 

####VPN conf file as a secret into your deployment:
1. a `subPath` will also need to be used in the
`volume` hash 
2. Your `secret` volume must contain the `items` array with the correct values.

[deployment.yaml](deployment.yaml) demonstrates `volume`, `volumeMounts`, and `secret` volume structured in this way.
    