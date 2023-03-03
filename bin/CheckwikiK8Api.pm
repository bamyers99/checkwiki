=begin
 Copyright 2023 Myers Enterprises II
 
 Licensed under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License.
 You may obtain a copy of the License at
 
 http://www.apache.org/licenses/LICENSE-2.0
 
 Unless required by applicable law or agreed to in writing, software
 distributed under the License is distributed on an "AS IS" BASIS,
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and
 limitations under the License.
=cut

use strict;
package CheckwikiK8Api;

use IO::Socket::SSL;
use HTTP::Request;
use LWP::UserAgent;

sub build_yaml {
    my ( $jobname, $command, $mem, $cpu ) = @_;
    $jobname =~ s/"/\\"/g;
    $command =~ s/"/\\"/g;
    
    my $yaml = <<"END_YAML";
    	{
        "apiVersion" : "batch/v1",
        "kind" : "Job",
        "metadata" : {
            "name" : "$jobname",
            "namespace" : "tool-checkwiki",
            "labels" : {
		        "toolforge" : "tool",
		        "app.kubernetes.io/version" : "1",
		        "app.kubernetes.io/managed-by" : "toolforge-jobs-framework",
		        "app.kubernetes.io/created-by" : "checkwiki",
		        "app.kubernetes.io/component" : "jobs",
		        "app.kubernetes.io/name" : "$jobname",
		        "jobs.toolforge.org/filelog" : "yes",
		        "jobs.toolforge.org/emails" : "none"
    			}
    	},
        "spec" : {
            "ttlSecondsAfterFinished" : 30,
            "backoffLimit" : 0,
            "template" : {
                "metadata" : {"labels" : {
			        "toolforge" : "tool",
			        "app.kubernetes.io/version" : "1",
			        "app.kubernetes.io/managed-by" : "toolforge-jobs-framework",
			        "app.kubernetes.io/created-by" : "checkwiki",
			        "app.kubernetes.io/component" : "jobs",
			        "app.kubernetes.io/name" : "$jobname",
			        "jobs.toolforge.org/filelog" : "yes",
			        "jobs.toolforge.org/emails" : "none"
	    			}
    			},
                "spec" : {
                    "restartPolicy" : "Never",
                    "containers" : [
                        {
                            "name" : "$jobname",
                            "image" : "docker-registry.tools.wmflabs.org/toolforge-perl532-sssd-base:latest",
                            "workingDir" : "/data/project/checkwiki",
                            "command" : ["/bin/sh", "-c", "--", "$command 1>>$jobname.out 2>>$jobname.err"],
                            "env" : [{"name" : "HOME", "value" : "/data/project/checkwiki"}],
                            "volumeMounts" :  [{"mountPath" : "/data/project", "name" : "home"}],
                            "resources" : {
                                "limits" : {"cpu" : "$cpu", "memory" : "$mem"},
                                "requests" : {"cpu" : "$cpu", "memory" : "$mem"}
                            }
                        }
                    ],
                    "volumes" : [
                        {
                        "name" : "home", "hostPath" : {"path" : "/data/project", "type" : "Directory"}
                        }
                    ]
                }
            }
        }
    }
END_YAML
    
    return $yaml;
}

sub send_yaml {
    my ( $yaml ) = @_;
	my $url = 'https://k8s.tools.eqiad1.wikimedia.cloud:6443/apis/batch/v1/namespaces/tool-checkwiki/jobs';
    my $response;
	my $req = HTTP::Request->new(POST => $url);
	$req->content_type('application/json');
	$req->content($yaml);

    my $ua = LWP::UserAgent->new;
    $ua->agent('checkwiki (k8s api)');
    $ua->default_header('Content-Type' => "application/json");
    $ua->default_header('Content' => $yaml);
    $ua->ssl_opts(verify_hostname => 0);
    $ua->ssl_opts(SSL_cert_file => '/data/project/checkwiki/.toolskube/client.crt');
    $ua->ssl_opts(SSL_key_file => '/data/project/checkwiki/.toolskube/client.key');
    $ua->ssl_opts(SSL_use_cert => 1);
    $ua->ssl_opts(SSL_verify_mode => SSL_VERIFY_NONE);
    
    $response = $ua->request($req);
	
	return $response;
}

1;