### Prerequisites
* Clone this repo into your WSL Environment as `Labs4`:
```bash
cd ~
git clone https://github.com/qa-tech-training/BOAQAAIP_DAY4_LABS.git Labs4
```

### Lab ANS04 - Playbook Performance Optimisation

#### Objective
Use ansible configuration options and advanced features of ansible to profile and optimise the performance of your playbooks

#### Outcomes
By the end of this lab, you will have:
* Configured performance profiling for Ansible playbooks
* Configured fact and inventory caching
* Configured performance-impacting SSH parameters

#### High-Level Steps
* Enable performance profiling
* Enable caching
* Set up SSH optimisations

#### Detailed Steps

##### Setup Instances
1. Switch into the ANS04 directory, and review the starting point for this lab:
```bash
cd ~/Labs4/ANS04
```

2. Provision the infrastructure with terraform:
```bash
cd terraform
terraform apply
```
##### Profiling playbook execution
3. Switch into the ansible directory:
```shell
cd ~/Labs4/ANS04/ansible
```
4. Before configuring the compute instances, edit the ansible.cfg file, adding the following line to the _defaults_ section:
```ini
    callbacks_enabled = timer, profile_tasks, profile_roles
```
5. Update the inventory and invoke the playbook:
```shell
ansible 127.0.0.1 -m template -a "src=$(pwd)/inventory.gcp_compute.template.yml dest=$(pwd)/inventory.gcp_compute.yml" -e "GCP_PROJECT=$TF_VAR_gcp_project"
ansible-playbook -i inventory.gcp_compute.yml playbook.yml -e "state=present"
```
6. Observe that ansible will provide a detailed breakdown of how long each task took to execute. This is useful information for figuring out where to start optimising performance.  

One possible source of performance optimisations is in the fact gathering that happens implicitly on each play by default. It is possible to disable fact gathering alltogether from within your playbook if you do not need it, but we are using the facts to template the nginx.conf file. Instead, we will configure *fact caching* to enable reuse of these values.  

7. Switch back to the terraform directory and destroy the resources:
```shell
cd ~/Labs4/ANS04/terraform
terraform destroy
```

##### Enable caching
8. Redeploy the resources with terraform:
```shell
terraform apply
```
9. then switch back into the ansible directory. Edit the ansible.cfg file again:
```ini
[defaults]
    remote_user = ansible
    private_key_file = ~/ansible_key
    callbacks_enabled = timer, profile_tasks, profile_roles
    fact_caching = jsonfile # <- add this and next two lines
    fact_caching_timeout = 3600
    fact_caching_connection = facts.d

[ssh_connection]
    ssh_args = -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null

[inventory] # <- add this section
    cache = true
    cache_plugin = jsonfile
    cache_timeout = 3600
    cache_connection = inventory.d
```
These changes have enabled two kinds of caching. Fact caching, as described, will reduce the amount of time spent gathering facts during playbook execution. Inventory caching will prevent ansible from having to regenerate the inventory via the plugin on every run. 
10. Execute the playbook:
```shell
ansible-playbook -i inventory.gcp_compute.yml playbook.yml -e "state=present"
```
11. Review the generated cache files to see the information that Ansible has stored

##### Exploiting Caching
The first run of the playbook with caching enabled will, if anything, probably have been a little slower, as Ansible has to write the data to the cache. It is on subsequent executions that you will see the benefit.  

12. Execute the playbook again, but this time set the state to absent, to uninstall packages:
```bash
ansible-playbook -i inventory.gcp_compute.yml playbook.yml -e "state=absent"
```
You should notice faster execution.  

13. To prove that the speedup was not simply down to uninstalling being faster than installing, edit the playbook.yml and change the install_dir variable value, to force ansible to re-clone the repo. Then re-run the playbook with state=present:
```bash
ansible-playbook -i inventory.gcp_compute.yml playbook.yml -e "state=present"
```

##### Optimising SSH
Another source of performance issues can be the time taken to establish SSH connections. We have already somewhat reduced this by disabling host key checking. But we can optimise the SSH configuration further. 
14. Re-execute the playbook with state=absent again, to uninstall packages
15. Before re-invoking the playbook, edit ansible.cfg again, like so:
```ini
[defaults]
  remote_user = ansible
  private_key_file = ~/ansible_key
  callbacks_enabled = timer, profile_tasks, profile_roles
  fact_caching = jsonfile
  fact_caching_timeout = 3600
  fact_caching_connection = facts.d

[ssh_connection]
  ssh_args = -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ControlMaster=auto -o ControlPersist=90s
  pipelining = True # <- add extra arguments to this line

[inventory]
  cache = true
  cache_plugin = jsonfile
  cache_timeout = 3600
  cache_connection = inventory.d
```
The additional ssh connection settings will cause connections to be left open for longer, allowing them to be reused across plays, and pipelining will make background operations more efficient. 
16. Edit the install_dir again, then re-invoke the playbook with state=present, and see if you observe a noticeable difference in performance:
```shell
ansible-playbook -i inventory.gcp_compute.yml playbook.yml -e "state=present"
```

##### Clean Up
17. Before moving on, destroy any resources:
```bash
cd ~/Labs4/ANS04/terraform
terraform destroy
```

### Lab ANS05 - Secret Management With Ansible-Vault

#### Objective
Securely store and retrieve sensitive data using ansible-vault

#### Outcomes
By the end of this lab, you will have:
* Created a vault file to securely store variables
* Retrieved data from a vault during playbook execution

#### High-Level Steps
* Deploy a sample app that requires authentication
* Use ansible to make an authenticated request to the app
* Store the credentials in a vault file
* Reconfigure the playbook to retrieve the credentials from the vault file

#### Detailed Steps
##### Deploy a Sample App
1. Ensure that the sample API is running - this is the same sample API we worked with previously:
```bash
sudo ss -tap | grep 5000 || sudo sh -c "docker compose -f ~/Labs2/PY05/compose.yml up -d --build"
```
2. Switch into the ANS05 directory and review the provided playbook:
```bash
cd ~/Labs4/ANS05
```
```yaml
---
- hosts: localhost
  connection: local
  name: Use Credentials
  tasks:
  - name: Make API Call
    uri:
      url: "http://localhost:5000/auth/tokens"
      method: "POST"
      url_username: "learner"
      url_password: "p@ssword"
      return_content: true
    register: result
  
  - name: print info
    debug:
      msg: "{{ result.content }}"
```
3. Execute the playbook:
```bash
ansible-playbook playbook.yml
```
4. You should see in the output a generated token, something like:
```
97506f8a1816434b5291a349f0dd5bd4574962ebf82f66505bccc87baf257ac3
```

##### Secure the Credential
Having a hardcoded password in the playbook like this is a problem, especially if we want to share that playbook with others. And simply passing the value as a variable on the command line is not an ideal solution, as this leaves the sensitive credential potentially exposed via command history. Instead, a better approach would be to use _ansible-vault_ to encrypt the data at rest, and retrieve it during playbook execution.  
5. Create a new vault file:
```bash
ansible-vault create vault.yml
```
6. Once you have set a password on the vault file itself, you will be presented with an editor. Add the following content:
```yaml
password: "p@ssword"
```
7. Then save and quit the editor. You now have a new vault file. Attempt to cat the contents:
```bash
cat vault.yml
```
8. You should see output similar to:
```
$ANSIBLE_VAULT;1.1;AES256
33313334323633626365616266313161636134343635313038396162666533376665666562323164
6361303938643739383338663631623538303933356630360a366666366661653866616537643761
66623737316632366435613435393666306661303536333236643335333062633063323531623533
3462653266643330370a656531326535616439633637666164376630646531366138623335663437
39333034343132326634376363363934323762316633393430383237363832626639
```
Demonstrating that the vault file has been encrypted.

##### Update the Playbook
9. Edit playbook.yml again, so that the contents are as follows:
```yaml
---
- hosts: localhost
  connection: local
  name: Use Credentials
  vars_files: # <- add this line
  - vault.yml # <- and this line
  tasks:
  - name: Make API Call
    uri:
      url: "http://localhost:5000/auth/tokens"
      method: "POST"
      url_username: "learner"
      url_password: "{{ password }}" # <- edit this line to reference the password variable
      return_content: true
    register: result
  
  - name: print info
    debug:
      msg: "{{ result.content }}"
```
10. Now re-run the playbook, but this time add the `-J` flag, which instructs ansible to prompt for the vault password:
```bash
ansible-playbook playbook.yml -J
```
You should again expect to see a token returned, if the request was successful.

##### Stretch Task
By consulting the [documentation](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/uri_module.html) for the uri module, and recalling how we interacted with the API previously, add extra tasks to the playbook which use the token received from the initial request to create, update and delete objects through the API. See the solution below if needed.  

##### Stretch Task Solution - POST /api/book
```yaml
---
- hosts: localhost
  connection: local
  name: Use Credentials
  vars_files: 
  - vault.yml
  tasks:
  - name: Make API Call
    uri:
      url: "http://localhost:5000/auth/tokens"
      method: "POST"
      url_username: "learner"
      url_password: "{{ password }}" 
      return_content: true
    register: result
  - name: Add book
    uri:
      url: "http://localhost:5000/api/books"
      method: "POST"
      headers:
        Authorization: "Bearer {{ result.content }}"
      body_format: json
      body:
        title: "Example"
        author: "John Smith"
        genre: "scifi"
        id: "0000012345"
      return_content: true
    register: result2
  - name: print info
    debug:
      msg: "{{ result2 }}"
```
Other requests to other endpoints will be similar

### Lab ANS06 - Introduction to AWX

#### Objective
Create a job in AWX to manage scheduled ansible executions

#### Outcomes
By the end of this lab, you will have:
* deployed an AWX cluster
* Configured credentials in AWX
* Configured an AWX job to run scheduled maintenance activities

#### High-Level Steps
* Deploy AWX
* Add an SSH key as a credential to AWX
* Create and run an AWX job

#### Detailed Steps
##### Deploy Resources
1. In your terminal, switch to the ANS06 directory: `cd ~/Labs4/ANS06`
2. Initialise Terraform and apply the provided resource configuration:
```bash
terraform init
terraform apply -auto-approve
``` 
This will provision the instances which AWX will configure.  

##### Deploy AWX
3. For performance reasons, we will run AWX on a local VM using Hyper-V. Launch Hyper-V and start the AWX VM.
4. Connect to the VM. The username and password are both 'qa'. Make a note of the VM's IP (run `ip addr show eth0 | grep "inet "`), and run the provided install_awx.sh script:
```bash
./install_awx_kind.sh
```
5. The AWX init script takes several minutes to run, after which AWX will need another several minutes to fully initialise. Take the time to review the [explanation](#the-awx-init-script-explained) of what the script is actually doing
6. Navigate to http://<awx_vm_ip>:30080 in a new browser tab. If AWX is still configuring, you may see connection refused or an internal server error - wait until the page reloads
7. Once AWX is finally ready, log in with the following credentials:
    * username: admin
    * password: ChangeMe123!
You should now see the AWX dashboard.

##### Create an AWX Job
1. In the AWX dashboard, create a new organisation:
    * Click on the Organizations under Access from the left side pane
    * Click Add button to Create New Organization
    * When prompted to enter Organization Name, enter `BOAAWX`
    * Click on Save
2. Return to the AWX dashboard and select Resources > Projects > add
3. Configure the project as follows:
    * name: site-sync
    * Organizations as `BOAAWX` 
    * SCM Type as "Git" 
    * repository as https://github.com/qa-tech-training/sample-awx-project 

##### Add SSH Credentials
To be able to connect to our machines, AWX will need access to the private SSH key that corresponds to the public key used to build the infrastructure.
1. Navigate to Resources > Credentials, click 'add'
2. Configure the new credential as follows:
    * name: ansible_ssh_key
    * organization: BOAAWX
    * credential type: machine
    * username: ansible
    * SSH Private Key: copy and paste in the material from ~/ansible_key
    * privilege escalation method: sudo
    * privilege escalation password: leave blank
3. Save the credential

##### Add an Inventory
1. Navigate to Resources > Inventory and click Add
2. Name the inventory 'webservers', and associate it to the BOAAWX organization, and save

We will keep things simple with a static inventory for now, but this could be dynamic via an inventory source
3. Click on Hosts
4. Add a host by clicking add. Enter the IP of one of your app servers
5. Repeat for the other app servers and the proxy server
6. Once you have added all your hosts, we need to group them, following the pattern gcp_role_<role>. From the inventory overview, click on Groups > add. Name the new group 'gcp_role_appserver'. 
7. Click on hosts > add, and select 'add existing host'. Then choose all of the IPs that correspond to your appserver instances
8. Create another new group called 'gcp_role_proxy'. Repeat the process to add existing hosts, this time selecting the IP of your proxy server.

##### Create a Job Template
1. Navigate to Resources > Templates, and click add.
2. Configure the following:
    * NAME: Deploy Site
    * Description : Ensure Site is Deployed
    * JOB TYPE: Run 
    * INVENTORY: webservers
    * PROJECT: site-sync
    * PLAYBOOK: ansible/playbook.yml
    * CREDENTIALS: ansible_ssh_key
    * VARIABLES:
    ```yaml
    repository_url: https://github.com/qa-tech-training/sample-awx-project
    ```
3. Save the template configuration, then run the job manually to test connectivity

##### Create a Schedule
Manually triggering job executions is not the preferred way to run AWX jobs, as it somewhat defeats the point of automation. AWX is excellent for scheduling jobs, to be run at specific times.
1. Select your job template, edit it and select `schedules`
2. Configure the schedule so that the job runs once per day 

###### The AWX Init Script Explained
The primary distribution mechanism for AWX is as a Kubernetes operator. Detailed understanding of Kubernetes is beyond the scope of this course, but in short it is the de-facto standard orchestration platform for containerised workloads. Running AWX through Kubernetes allows for highly available, scalable deployments of the workloads needed to execute AWX jobs. To set up AWX, the init script does the following:
* installs and configures _docker_, a common container management tool
* installs *k*ubernetes-*in*-*d*ocker (KinD), a tool for running a Kubernetes cluster as a set of containers
* Creates a KinD cluster with appropriate ports mapped
* Deploys the AWX operator and associated resources into the KinD cluster
[back to instructions](#deploy-awx)

### Lab ANS07 - Configuring AWX to Work With Hashicorp Vault

#### Objective
Deploy Hashicorp Vault and use it to store credentials

#### Outcomes
By the end of this lab, you will have:
* Deployed hashicorp vault in development mode
* Created a Vault secret
* Configured AWX to retrieve a secret from a vault

#### High-Level Steps
* Deploy Hashicorp vault
* move SSH key into vault
* Reconfigure AWX jobs to read credentials from vault

#### Detailed Steps
##### Deploy Vault
1. In WSL, switch into the ANS07 directory, and run the following to deploy a vault server:
```bash
cd ~/Labs4/ANS07
terraform init
terraform apply -auto-approve
```
2. Make a note of the output `vault_ip` value, and also the root token that this vault installation has been deployed with: example-vault-token-1234. We will use these in the next step.

##### Store a Credential
Let's store our first credential in vault. We will start by storing the private SSH key that we have been using for ansible jobs. 
3. Run the following in your WSL terminal, *making sure to fill in your vault server IP*:
```bash
export VAULT=<your vault IP>
export VAULT_TOKEN=example-vault-token-1234
echo "{\"data\": {\"sshkey\":\"$(cat ~/ansible_key)\"}}" > data.json
curl \
    -H "X-Vault-Token: $VAULT_TOKEN" \
    -H "Content-Type: application/json" \
    -XPOST \
    -d@data.json \
    http://$VAULT:8200/v1/secret/data/ansible-ssh-key
```
4. Verify the credential creation:
```bash
curl \
    -H "X-Vault-Token: $VAULT_TOKEN" \
    http://$VAULT:8200/v1/secret/data/ansible-ssh-key > secret.json
cat secret.json
```

##### Configure AWX to Retrieve Credentials from Vault
1. Return to your AWX dashboard and navigate to the credentials overview.
2. Create a new credential with the following configuration:
    * type: HashiCorp Vault Secret Lookup
    * name: vault_credential
    * URL: http://<your vault server IP>:8200
    * Token: example-vault-token-1234
    * API version: v1
3. Save this credential and return to the credentials overview
4. Edit the configuration for the credential you created earlier:
    * Input sources: choose the new credential you just created
    * Input field: SSH Private Key
    * secret path: /data/ansible-ssh-key
    * secret key: sshkey
5. Return to the job template you defined earlier and trigger a new execution, to test the connectivity with the key now pulled from vault.

### Optional Stretch Lab
* In Hyper-V, start the 3 Centos VMs
* Generate a new SSH key pair, and:
  * place the _public key_ material in the authorized_keys file (`/home/qa/.ssh/authorized_keys`) on each of the centos VMs
  * store the _private key_ material as a new vault credential, and create a new AWX credential with the username 'qa', privilege escalation method 'sudo', privilege escalation password 'qa', and your new vault credential as its' source
* Create a Github Account if you do not already have one, and sign in
* fork the https://github.com/qa-tech-training/sample-awx-project repo. Update the tasks for the _common_ role to work on centos instead of ubuntu. (hint: see documentation for the ansible.builtin.yum module)
* Add a new AWX project which uses _your fork_ of the sample repo as a source
* add a new AWX inventory with the hostnames of the three centos VMs. Create groups gcp_role_appserver and gcp_role_proxy, allocating one of the VMs as the proxy and the other two as app servers
* Create a new job definition to run the playbook against the centos VMs. If successful, the job when run should deploy the same sample website onto the centos VMs
