use YAML::XS;
use Parse::CSV;
use JSON;
use Data::Dumper;
use Time::Local;
use Date::Parse;
use WWW::Curl::Easy;
use WWW::Curl::Multi;
use DBI;
use POSIX;
use strict;

# ----  move to bill.pm ---
sub get_cred
    {
    my $file=shift;
    my $n=shift;
    my $type;
    my $endpt;
    my $user;
    my $pass;
    my $pg_user;
    my $pg_pass;
    my $fp;
    if(open(FP, "<$file"))
        {
        my $cnt=0;
        my $line=<FP>;
        while($cnt < $n)
            {
            $line=<FP>;
            $cnt=$cnt+1;
            }
        if($line =~ /[ \t]*stack[ ]*=[ ]*([^ \t\n]*)[ ]*[,\t]*/) { $type='stack'; $endpt=$1; }
        if($line =~ /[ \t]*username[ ]*=[ ]*([^ \t\n]*)[ ]*[,\t]*/) { $user=$1; }
        if($line =~ /[ \t]*password[ ]*=[ ]*([^ \t\n]*)[ ]*[,\t]*/) { $pass=$1; }
        if($line =~  /[ \t]*pg_user[ ]*=[ ]*([^ \t\n]*)[ ]*[,\t]*/) { $pg_user=$1; }
        if($line =~  /[ \t]*pg_pass[ ]*=[ ]*([^ \t\n]*)[ ]*[,\t]*/) { $pg_pass=$1; }
        }
    else
        {
        print "Error: cannot open file \"$file\"\n";
        exit();
        }
    return ($type, $endpt, $user, $pass, $pg_user, $pg_pass);
    }

sub get_conn
    {
    my $user=shift;
    my $pass=shift;

    my $conn = DBI->connect("dbi:Pg:dbname=postgres",$user,$pass);
    return $conn;
    }

sub del_conn
    {
    my $conn=shift;
    if($conn) 
        {
        $conn->disconnect();
        $conn = undef;
        }
     }

sub open_csv
    {
    my $fname=shift;
    # print STDERR "--> $fname\n\n";
    my $csv_handel=Parse::CSV->new(file=>$fname,names=>1);    
    return $csv_handel;
    }

# ---- end of bill.pm ----

# $projects->uuid = [project uuid]
#                ->name = [project name]
#                ->id   = [project id in cloud forms (will go away)]
#                ->VM   = [hash of VMs in this project (added later)] MVP
#                ->Vol  = [hash of the Volumes in this project (added later)] MVP
#                ->Obj  = [hash of the object stores in this project (added later)]
#          ->os_id->Con  = [has of the containers in this project (added later) ]

sub read_projects
    {
    my $fname=shift;
    my $proj;

    my $data_set=open_csv($fname);

    # id,name,ems_ref,ems_id,description
    while(my $line=$data_set->fetch())
        {
        my $id=$line->{'id'};
        $proj->{$id}->{'name'} = $line->{'name'};
        $proj->{$id}->{'uuid'} = $line->{'ems_ref'};
        $proj->{$id}->{'vm_cnt'} = 0;
        $proj->{$id}->{'vol_cnt'} = 0;
        $proj->{$id}->{'event_cnt'} = 0;
        #$proj->{$id}->{} = $line{'ems_id'};
        }
    #print Dumper($proj);
    return $proj;
    }

sub read_flavors
    {
    my $fname=shift;
    my $flavor;

    my $data_set=open_csv($fname);
    # id,name,cpus,memory,root_disk_size,ems_ref
    while(my $line=$data_set->fetch())
        {
        my $id=$line->{'id'};
        $flavor->{$id}->{'name'}=$line->{'name'};
        $flavor->{$id}->{'cpus'}=$line->{'cpus'};
        $flavor->{$id}->{'mem'}=$line->{'memory'}/1073741824;
        $flavor->{$id}->{'disk'}=1.0*$line->{'root_disk_size'}/1073741824;
        $flavor->{$id}->{'cost'}= 0.1*$line->{'cpus'} + 0.2*$flavor->{'mem'};
        }
    return $flavor;
    }

# This takes a projct datastructure and adds in the VM information
sub read_vms
    {
    my $proj=shift;
    my $fname=shift;
    
    my $data_set=open_csv($fname);
    #id,name,guid,flavor_id,tenant_id
    while(my $line=$data_set->fetch())
        {
        my $proj_id = $line->{'tenant_id'};
        #my $uuid = $line->{'guid'};
        my $uuid = $line->{'id'};
        $proj->{$proj_id}->{'vm_cnt'}=1; # just set this to 1 for now.
        $proj->{$proj_id}->{'VM'}->{$uuid}->{'event_cnt'}=0;
        $proj->{$proj_id}->{'VM'}->{$uuid}->{'name'}=$line->{'name'};
        $proj->{$proj_id}->{'VM'}->{$uuid}->{'flavor_id'}=$line->{'flavor_id'};
        $proj->{$proj_id}->{'VM'}->{$uuid}->{'id'}=$line->{'id'};
        $proj->{$proj_id}->{'VM'}->{$uuid}->{'id'}=$line->{'guid'};
        }

    # count up the VMs
    # not yet though.
    return $proj;
    }
 
sub read_vol
    {
    my $proj=shift;
    my $fname=shift;
    
    my $data_set=open_csv($fname);
    #id,name,ems_ref,cloud_tenant_id,volume_type
    while(my $line=$data_set->fetch())
        {
        my $proj_id = $line->{'cloud_tenant_id'};
        my $uuid = $line->{'id'};
        $proj->{$proj_id}->{vol_cnt}=1;
        $proj->{$proj_id}->{'VOL'}->{$uuid}->{'name'}=$line->{'name'};     
        $proj->{$proj_id}->{'VOL'}->{$uuid}->{'type'}=$line->{'volume_type'};     
        $proj->{$proj_id}->{'VOL'}->{$uuid}->{'type'}=$line->{'ems_ref'};    # this is the openstack uuid     
        #$proj->{$proj_id}->{'VOL'}->{$uuid}->{'size'}=$line->{'size'};     
        
        }
    return $proj;
    }


# stage2 process how long it has been used

# data->$project_id->project_name
#                  ->user_id->username
#                           ->$instance_id->instance_name
#                                         ->{timestamp}->event_type
#                                                      ->vCPU
#                                                      ->mem
#                                                      ->disk
sub process_oslo_json
    {
    my $json_string=shift;
    my $data;
    if($json_string =~ /^'(.*)'$/) { $json_string=$&; }
    my $eq = from_json($json_string);
    #print Dumper($eq);
    #print("_context_domain=".$eq->{_context_domain}."\n");

    #find the project_id
    my $project_id=$eq->{_context_project_id};
    if(!$project_id) { $project_id=$eq->{payload}->{tenant_id}; }
    if(!$project_id) { $project_id=$eq->{payload}->{project_id}; }

    my $user_id=$eq->{_context_user_id};
    if(!$user_id) { $user_id=$eq->{payload}->{user_id};}

    $data->{timestamp} = $eq->{timestamp};
    $data->{project_id} = $project_id;
    $data->{instance_id} = $eq->{payload}->{instance_id};
    $data->{user_id} = $user_id;
    $data->{cpu} = $eq->{payload}->{vcpus};
    $data->{mem} = $eq->{payload}->{memory_mb};
    $data->{root_gb} = $eq->{payload}->{root_gb};
    $data->{state} = $eq->{payload}->{state};
    $data->{flavor} = $eq->{payload}->{instance_type};
    return $data;
    }

sub process_vm_msg
    {
    my $msg=shift;
    my $data;
    my $eq;
   
    $msg =~ /\-\-\-/;
    $msg =~ $';
    # print "-->".$msg."\n";
    my $yaml=YAML::XS::Load $msg;
    # print Dumper($yaml);
    if(exists $yaml->{':content'} and exists $yaml->{':content'}->{'oslo.message'})
        {
        $data=process_oslo_json($yaml->{':content'}->{'oslo.message'});
        }
    elsif( exists $yaml->{':content'} and exists $yaml->{':content'}->{'payload'})
        {
        $data->{timestamp} = $yaml->{timestamp};
        $data->{project_id} = $yaml->{payload}->{project_id};
        if(!($data->{project_id})) { $data->{project_id} = $yaml->{':content'}->{payload}->{tenant_id}; }
        $data->{instance_id} = $yaml->{':content'}->{payload}->{instance_id};
        $data->{user_id} = $yaml->{':content'}->{payload}->{user_id};
        $data->{cpu} = $yaml->{':content'}->{payload}->{vcpus};
        $data->{mem} = $yaml->{':content'}->{payload}->{memory_mb};
        $data->{root_gb} = $yaml->{':content'}->{payload}->{root_gb};
        $data->{state} = $yaml->{':content'}->{payload}->{state};
        }
    return $data;
    }

sub build_instace_to_proj_index
    {
    my $proj=shift;
    my $index;

    foreach my $proj_id (keys $proj)
        {
        if($proj->{$proj_id}->{vm_cnt}>0)
            {
            my $vms = $proj->{$proj_id}->{VM};
            foreach my $vm_id (keys $vms)
                {
                $index->{$vm_id}=$proj_id;
                }
            } 
        }
    return $index;
    }

sub get_metrics_data
    {
    my $proj=shift;
    my $fname=shift;
    my $start_ts=shift;
    my $end_ts=shift;

    my $data_set=open_csv($fname);
    # timestamp, resource_id, resource_type, cpu_usage_rate_average,capture_interval,capture_interval_name 
    while(my $line=$data_set->fetch())
        {
        my $ts = $line->{'timestamp'};

        my $t=str2time($ts);
        my $st=str2time($start_ts);
        my $et=str2time($end_ts);
        my $i2p=build_instace_to_proj_index($proj);

        if($st <= $t and $t <= $et)
            {

            if($line->{'capture_interval_name'} eq 'Hourly' and $line->{'resource_type'} eq 'VmOrTemplate')
                {
                # print "$ts --> $proj_id  [ $msg->{instance_id} ]\n";
                my $uuid=$line->{resource_id};

                my $proj_id = $i2p->{$uuid};  # becuase there is no project id in the metrics table
                $proj->{$proj_id}->{'VM'}->{$uuid}->{event_cnt}=1;

                #add in the instance id to the hash right before the $ts
                if($line->{'cpu_usage_rage_average'}>0) 
                    {
                    $proj->{$proj_id}->{'VM'}->{$uuid}->{events}->{$ts}->{_id}=1;
                    }
                #print "$msg->{instance_id}, $msg->{cpu}, $msg->{mem} \n";
                #print "-------\n"
                }
            }
        }
    return $proj;
    }

sub get_mq_data
    {
    my $proj=shift;
    my $fname=shift;
    my $start_ts=shift;
    my $end_ts=shift;
    
    my $data_set=open_csv($fname);
    # id,ems_id,event_type,timestamp,full_data
    while(my $line=$data_set->fetch())
        {
        my $ts = $line->{'timestamp'};
        
        my $t=str2time($ts);
        my $st=str2time($start_ts);
        my $et=str2time($end_ts);

        if($st <= $t and $t <= $et)
            {
            
            if($line->{'event_type'} =~ /compute.instance.exists/)
                {
                my $proj_id = $line->{'ems_id'};
                my $msg=process_vm_msg($line->{'full_data'});
                # print "$ts --> $proj_id  [ $msg->{instance_id} ]\n";
                my $uuid=$msg->{instance_id};
                $proj->{$proj_id}->{'VM'}->{$uuid}->{event_cnt}=1;
            

                #add in the instance id to the hash right before the $ts
                $proj->{$proj_id}->{'VM'}->{$uuid}->{events}->{$ts}->{instance_id}=$msg->{instance_id};
                $proj->{$proj_id}->{'VM'}->{$uuid}->{events}->{$ts}->{cpu}=$msg->{cpu};
                $proj->{$proj_id}->{'VM'}->{$uuid}->{events}->{$ts}->{mem}=$msg->{mem};
                $proj->{$proj_id}->{'VM'}->{$uuid}->{events}->{$ts}->{root_gb}=$msg->{root_gb};
                $proj->{$proj_id}->{'VM'}->{$uuid}->{events}->{$ts}->{state}=$msg->{state};
                #print "$msg->{instance_id}, $msg->{cpu}, $msg->{mem} \n";
                #print "-------\n"
                }
            if($line->{'event_type'} =~ /volume/)
                {
                my $proj_id = $line->{'ems_id'};
                my $ts = $line->{'timestamp'};
                #print "found a $line->{'event_type'} \n";
                }
            }
        }
    return $proj;
    }



# tally hours
# 1) find the first event
#    a) power-on -> $start_time = power-on timestamp, power_on=1
#    b) power-off - $start_time = $t1, $end_time = power-off timestamp; $amt= time diff ($start_time, $end_time); $start_time=undef, $end_time=undef; power_on=0;
#    c) exists status=active $start_time=$t1 power_on=1
#    d) exists status!=active power_on=0;
#
# 2) for each event
#    a) if power_on == 1
#       i) power_on -> issue a warning
#          $end_time=$last event; $amt=timediff($start_time,$end_time); $start_time=this->timestamp; $end_time=undef; power_on=0;
#       ii) power_off -> 
#          $end_time=$this event; $amt=timediff($start_time,$end_time); $start_time=undef; $end_time=undef; power_on=0;
#       iii) exists = active ->
#             $end_time=this event;
#       iv) exists != active -> issue a warning
#          $end_time=$last event; $amt=timediff($start_time,$end_time); $start_time=this->timestamp; $end_time=undef; power_on=0;
#    b) if power_on == 0
#       i) power_on -> 
#          $end_time=$this event; $amt=timediff($start_time,$end_time); $start_time=undef; $end_time=undef; power_on=0;
#       ii) power_off-> issue a warning
#          power_on=0;
#       iii) exists = active -> issue a warning (we missed the power on even - start from here)
#             $start_time=this event; power_on=1
#       iv) exists != active -> 
#           power_on=0;
#
#  This needs to be reworked
#  
#
sub tally_hours
    {
    my $events=shift;
    my $t1=shift;
    my $t2=shift;

    my $start_time=undef;
    my $end_time=undef;
    my $power_on;
    my $total_time_on;
    my $time_on;
    
    my @ts = (sort keys $events);
    my $t = pop @ts;
    my $t2 = $events->{$t}->{end_ts};
    if($events->{$t}->{event_type} eq 'exists' and $events->{$t}->{status} eq 'acitive')
        {
        $start_time=$t1;
        $end_time=$t2;
        $power_on=1;
        }
    elsif($events->{$t}->{event_type} eq 'exists' and $events->{$t}->{status} ne 'acitive')
        {
        $start_time=undef;
        $end_time=undef;
        $power_on=0;
        }   
    elsif($events->{$t}->{event_type} eq 'power.on' and $events->{$t}->{status} eq 'acitive')
        {
        $start_time=$t; $end_time=undef;
        $power_on=1;
        }
    elsif($events->{$t}->{event_type} eq 'power.off' and $events->{$t}->{status} ne 'acitive')
        {
        $start_time=$t1;       $end_time=$t2;
        $time_on=timediff($start_time,$end_time);
        $total_time_on+=$time_on;
        # log this!!!
        $start_time=undef;     $end_time=undef;
        $power_on=0;
        }
    #print STDERR $events->{$t}->{event_type}." ".$events->{$t}->{status}."  ".$start_time."   ".$end_time."  ".$power_on."\n";
    foreach $t (@ts)
        {
        if($power_on==1)
            {
            if($events->{$t}->{event_type} eq 'exists' and $events->{$t}->{status} eq 'acitive')
                {
                $end_time=$t2;
                $power_on=1;
                }
            elsif($events->{$t}->{event_type} eq 'exists' and $events->{$t}->{status} ne 'acitive')
                {
                # warning (going from power_on state to inactive - missed the power off?
                $time_on=timediff($start_time,$end_time);
                $total_time_on=$time_on;
                # log this !!!
                $start_time=undef;
                $end_time=undef;
                $power_on=0;
                }
            elsif($events->{$t}->{event_type} eq 'power.on' and $events->{$t}->{status} eq 'acitive')
                {
                # warning powered on state and turning the power on again - missed the power off?
                $time_on=timediff($start_time,$end_time);
                $total_time_on=$time_on;
                # log this !!!
                $start_time=$t1;
                $power_on=1;
                }
            elsif($events->{$t}->{event_type} eq 'power.off' and $events->{$t}->{status} ne 'acitive')
                {
                $end_time=$t1;
                $time_on=timediff($start_time,$end_time);
                $total_time_on+=$time_on;
                # log this!!!
                $start_time=undef;     $end_time=undef;
                $power_on=0;
                }
            }
        elsif($power_on==0)
            {
            if($events->{$t}->{event_type} eq 'exists' and $events->{$t}->{status}='acitive')
                {
                # warn - missed the power on event
                $start_time=$t;
                $end_time=$t;
                $power_on=1;
                }
            elsif($events->{$t}->{event_type} eq 'exists' and $events->{$t}->{status}!='acitive')
                {
                $start_time=undef;
                $end_time=undef;
                $power_on=0;
                }
            elsif($events->{$t}->{event_type} eq 'power.on' and $events->{$t}->{status}='acitive')
                {
                $start_time=$t; $end_time=$t;
                $power_on=1;
                }
            elsif($events->{$t}->{event_type} eq 'power.off' and $events->{$t}->{status}!='acitive')
                {
                # warn 2 power is off, and a power off event occured.  missed the power on - nothing to tally.
                $start_time=undef;     $end_time=undef;
                $power_on=0;
                }
            }
        #print STDERR $events->{$t}->{event_type}." ".$events->{$t}->{status}."  ".$start_time."   ".$end_time."  ".$power_on."\n";
        }
    return $total_time_on
    }

sub tally_hours2
    {
    my $events=shift;
    my $flav=shift;
    my $t1=0;
    my $t2=0;

    my $start_time=undef;
    my $end_time=undef;
    my $power_on;
    my $total_time_on=0;
    my $total_amt=0.0;

    my @ts = (sort keys $events);
    my $t = pop @ts;
    $t1 = str2time($t);
    $t2 = str2time($events->{$t}->{end_ts});

    if($t2-$t1 < 0) 
        {
        print STDERR "bad time range\n";
        return 0;  
        }

    if($events->{$t}->{event_type} =~ /exists/ and $events->{$t}->{state} eq 'active')
        {
        $start_time=$t1;
        $end_time=$t2;
        if($t2 - $t1 < 3600) { $end_time = $t1 + 3600; }
        $power_on=1;
        }
    elsif($events->{$t}->{event_type} =~ /exists/ and $events->{$t}->{state} ne 'active')
        {
        $start_time=undef;
        $end_time=undef;
        $power_on=0;
        }
    foreach my $t (@ts)
        {
        if($events->{$t}->{event_type} =~ /exists/ and $events->{$t}->{state} eq 'active')
            {
            if($end_time > $t2) 
                {
                # do nothing
                #
                #   (t1' t2')  (t1', t2'')     (endtime (t1'+1hour))
                }
            if($end_time < $t1)
                {
                #   (t1' t2')    (t1'+1hour)      (t1'', t2'')
                #   (t1'                t2')      (t1'', t2'')
                $total_time_on += ($end_time - $start_time);
                $start_time=$t1;
                $end_time=$t2;
                if($end_time-$start_time<3600) { $end_time=$start_time+3600; }
                }
            if($t1 <= $end_time && $end_time < $t2)
                {
                #   (t1'            $t2')
                #                  ($t1''        t2'')
                $end_time=$t2
                }
            $start_time=$t1;
            $end_time=$t2;
            if( $t2 - $t1 < 3600) { $end_time = $t1 + 3600; }
            $power_on=1;
            }
        elsif($events->{$t}->{event_type} =~ /exists/ and $events->{$t}->{state} ne 'active')
            {
            $total_time_on += ($end_time - $start_time);
            $start_time=undef;
            $end_time=undef;
            $power_on=0;
            }
        }
    $total_time_on += ($end_time - $start_time);
    return (ceil($total_time_on/3600.0), 0.0);
    }

sub vm_subsection
    {
    my $vm=shift;
    my $flav=shift;
    my $t1=shift;
    my $t2=shift;
    my $flav=shift;
    my $total_hours=0;
    my $total_amt=0.00;
    my $rpt;
    my $amp=0.0;

    $rpt = "\\begin{table}[htbp]\n"
           ."\\begin{tabular}{l l r r }\n"
           ."VM Name & VM ID & Hours & Amt \\\\\n";

    foreach my $vm_id (sort keys $vm)
        {
        my $hours;
        my $amt;
        if($vm->{$vm_id}->{event_cnt}>0)
            {
            ($hours, $amt) = tally_hours2($vm->{$vm_id}->{events}, $flav);
            }
        else
            {
            $hours=0; $amt=0.0;
            }
        $total_hours+=$hours;
        #$total_amp=$total_amt+$amt;
        $rpt=$rpt."$vm->{$vm_id}->{name} & $vm_id & $hours & $amt\\\\\n";
        }
    $rpt=$rpt."VM Totals & & $total_hours &";
    $rpt=$rpt."\\end{tabular}\n"
             ."\\end{table}\n";
    return ($rpt, $total_amt);
    }

# Yes this combines both the project report and tallying up for the project report
# To split this would require similar work to be done in each
sub gen_project_reports
    {
    my $os_info = shift;
    my $flav = shift;
    my $proj_rpt_filename=shift;
    my $t1=shift;
    my $t2=shift;
    my $rpt;  # this is just a string containing the latex for the report.
    my $sub_total;
    my $total=0;

    $rpt="\\documentclass[10pt]{article}\n"
        ."\\usepackage [margin=0.5in] {geometry}\n"
        ."\\pagestyle{empty}\n"
        ."\\usepackage{tabularx}\n"
        ."\%\\usepackage{doublespace}\n"
        ."\%\\setstretch{1.2}\n"
        ."\\usepackage{ae}\n"
        ."\\usepackage[T1]{fontenc}\n"
        ."\\usepackage{CV}\n"
        ."\\begin{document}\n";

    my $proj=$os_info->{project};
    foreach my $proj_id (sort keys %{$proj})
        {
        $rpt= $rpt."\\begin{flushleft} \\textbf{\\textsc{OCX Project Report}}\\end{flushleft}\n"
             ."\\begin{flushleft} \\textsc{  Project: $proj->{$proj_id}->{name} id: $proj_id }\\end{flushleft}\n"
             ."\\flushleft{ \\textsc{     From: ".$t1."}}\n"
             ."\\flushleft{ \\textsc{     To: ".$t2."}}\n"
             ."\\newline\n";
        if($proj->{$proj_id}->{vm_cnt}>0)
            {
            my $sub_rpt;
            ($sub_rpt, $sub_total) = vm_subsection($proj->{$proj_id}->{VM},$flav,$t1,$t2);
            
            $rpt=$rpt.$sub_rpt;
            }
        else
            {
            $sub_total=0;
            }
        $total+=$sub_total;
        # vol_reports($proj->{$proj_id}->{Vol});
        # present a grand total
        $rpt=$rpt."";
        $rpt=$rpt."\\pagebreak\n";
        }
    $rpt=$rpt."\\end{document}";

    if(open(FP,">$proj_rpt_filename"))
        {
        print FP $rpt;
        }
    else
        {
        print STDERR "\n\n".$rpt."\n\n";
        }
    }



# get an openstack toke from keystone from the username/passowrd stored in 
# /etc/RBB/openstack.conf
sub get_unscoped_token
    {
    my $auth_url=shift;
    my $user=shift;
    my $pass=shift;
    my $token;
    my $resp;

    my $url="$auth_url/v3/auth/tokens";
    my $post_fields='{"auth": {"scope": {"unscoped": {}}, "identity": {"password": {"user": {"domain": {"id": "Default"}, "password": "'.$pass.'", "name": "'.$user.'"}}, "methods": ["password"]}}}';
    my $post_fields='{"auth": {"identity": {"password": {"user": {"domain": {"name": "Default"}, "password": "'.$pass.'", "name": "'.$user.'"}}, "methods": ["password"]}}}';
    # {"auth": {"scope": {"unscoped": {}}, "identity": {"password": {"user": {"domain": {"id": "Default"}, "password": "pass", "name": "mee"}}, "methods": ["password"]}}}

    my $curl=new WWW::Curl::Easy;
    $curl->setopt(CURLOPT_URL,$url);
    $curl->setopt(WWW::Curl::Easy::CURLOPT_HTTPHEADER(),["Content-Type: application/json"]);
    $curl->setopt(CURLOPT_POSTFIELDS,$post_fields);
    $curl->setopt(CURLOPT_HEADER,1);
    $curl->setopt(CURLOPT_WRITEDATA, \$resp);
    $curl->perform();
    
    my $err=$curl->errbuf;
    my $json;    

    foreach my $l (split /\n/,$resp)
        { 
        if($l =~ /X-Subject-Token: ([a-zA-Z0-9\-_]+)/) { $token=$1; print "token: $1\n"; }
        $json=$l; #this is a simple stupid way of setting $json_str to the last element of the array.
        }

    print "$url $user -> $resp\n";
    my $json_fields=from_json($json);
    #print Dumper($json_fields);
    my $ret;
    $ret->{user_id}=$json_fields->{token}->{user}->{id};
    $ret->{token}=$token;
    return $ret;
    }

sub get_scoped_token
    {
    my $auth_url=shift;
    my $unscoped_token=shift;
    my $project_id=shift;
    my $resp;
    my $ret;

    my $url=$auth_url."/v3/auth/tokens";
    my $post_fields='{"auth": {"scope": {"project": {"id": "'.$project_id.'"}}, "identity": {"token": {"id": "'.$unscoped_token.'"}, "methods": ["token"]}}}';

    my $curl=new WWW::Curl::Easy;
    $curl->setopt(CURLOPT_URL,$url);
    $curl->setopt(WWW::Curl::Easy::CURLOPT_HTTPHEADER(),["Content-Type: application/json"]);
    $curl->setopt(CURLOPT_POSTFIELDS,$post_fields);
    $curl->setopt(CURLOPT_HEADER,1);
    $curl->setopt(CURLOPT_WRITEDATA, \$resp);
    $curl->perform();

    my $err=$curl->errbuf;
    my $json;

    foreach my $l (split /\n/,$resp)
        {
        if($l =~ /X-Subject-Token: ([a-zA-Z0-9\-_]+)/) 
            { 
            $ret->{token}=$1; 
            #print "token: $1\n"; 
            }
        $json=$l; #this is a simple stupid way of setting $json_str to the last element of the array.
        }
    #print $url."--".$json."\n";
    my $json_fields=from_json($json);
    $ret->{catalog}=$json_fields->{token}->{catalog};
    return $ret;
    }
#using previousily obtained user_id and token, get the projects
#
sub get_os_projects
    {
    my $auth_url=shift;
    my $os_info=shift;
    my $resp;
    my $url="$auth_url/v3/users/".$os_info->{user_id}."/projects";
    my $json;

    
    my $curl=new WWW::Curl::Easy;
    $curl->setopt(CURLOPT_URL,$url);
    $curl->setopt(WWW::Curl::Easy::CURLOPT_HTTPHEADER(),["X-Auth-Token: $os_info->{token}"]);
    $curl->setopt(CURLOPT_HEADER,1); 
    $curl->setopt(CURLOPT_WRITEDATA, \$resp);
    $curl->perform();
    
    my $err=$curl->errbuf;
    my @resp=(split /\n/,$resp);
    my $json_fields=from_json($resp[-1]);
    foreach my $p (@{$json_fields->{projects}})
        {
        if( $p->{name} eq 'admin')
            {
            $os_info->{admin}->{id}=$p->{id};
            $os_info->{admin}->{domain}=$p->{domain_id};
            }
        else
            {
            $os_info->{project}->{$p->{id}}->{name}=$p->{name};
            $os_info->{project}->{$p->{id}}->{domain}=$p->{domain_id};
            }
        }
    return $os_info;
    }


# This needs to be generalized
# currently only accepts the admin token;
sub get_os_flavors
    {
    my $os_info=shift;
    my $endpt=find_in_catalog("nova",$os_info->{admin}->{catalog});
    my $url=$endpt."/flavors/detail";
    my $resp;
    my $flavor;

    if(!(exists $os_info->{admin}->{token}))
        {
        warn "get os_flavors(...) needs to be generalized to take any token\n";
        return undef;
        }

    my $curl=new WWW::Curl::Easy;
    $curl->setopt(CURLOPT_URL,$url);
    $curl->setopt(WWW::Curl::Easy::CURLOPT_HTTPHEADER(),["X-Auth-Token: $os_info->{admin}->{token}"]);
    $curl->setopt(CURLOPT_WRITEDATA, \$resp);
    $curl->perform();

    my $err=$curl->errbuf;
    #print "$err - $resp\n";
    my $flavor_array=from_json($resp);
    foreach my $f (@{$flavor_array->{flavors}})
        {
        $flavor->{$f->{id}}->{name}=$f->{name};
        $flavor->{$f->{id}}->{vcpus}=$f->{vcpus};
        $flavor->{$f->{id}}->{ram}=$f->{ram};
        $flavor->{$f->{id}}->{disk}=$f->{disk};
        }
    return $flavor;
    }

sub get_all_projects
    {
    my $auth_url;
    my $os_info=shift;
    my $endpt="/v3/projects";
    my $url=$auth_url.$endpt;
    my $resp;
    
    if( not (exists $os_info->{admin}->{token} ) )
        {
        my $tac=get_scoped_token($auth_url,$os_info->{token},$os_info->{admin}->{id});
        $os_info->{admin}->{token}=$tac->{token};
        $os_info->{admin}->{catalog}=$tac->{catalog};
        }
    my $url=find_in_catalog("keystone",$os_info->{admin}->{catalog});
    $url=$url.$endpt;

    my $curl=new WWW::Curl::Easy;
    $curl->setopt(CURLOPT_URL,$url);
    $curl->setopt(WWW::Curl::Easy::CURLOPT_HTTPHEADER(),["X-Auth-Token: $os_info->{admin}->{token}"]);
    $curl->setopt(CURLOPT_WRITEDATA, \$resp);
    $curl->perform();
    
    my $json_fields = from_json($resp);
    #print Dumper %$json_fields;
    #exit;
    foreach my $p (@{$json_fields->{projects}})
        {
        $os_info->{project}->{$p->{id}}->{name}=$p->{name};
        $os_info->{project}->{$p->{id}}->{domain}=$p->{domain_id};
        }
    return $os_info;
    }

sub get_add_project
    {
    my $os_info=shift;
    my $project_uid=shift;
    my $endpt="/v3/projects/";
    my $url="";
    my $resp;
    
    if( (exists $os_info->{project}) and (exists $os_info->{project}->{$project_uid}) )
        {
        # no need to continue - project is already there
        return $os_info;
        }

    if( not (exists $os_info->{admin}->{token} ) )
        {
        print "WARNING: call to get_add_project does not have admin token - continuing\n";
        return $os_info;
        }
    
    my $url=find_in_catalog("keystone",$os_info->{admin}->{catalog});
    $url=$url.$endpt.$project_uid;
    
    my $curl=new WWW::Curl::Easy;
    $curl->setopt(CURLOPT_URL,$url);
    $curl->setopt(WWW::Curl::Easy::CURLOPT_HTTPHEADER(),["X-Auth-Token: $os_info->{admin}->{token}"]);
    $curl->setopt(CURLOPT_WRITEDATA, \$resp);
    $curl->perform();
    
    my $json_fields = from_json($resp);
    if( (exists $json_fields->{error}) and (exists $json_fields->{error}->{code}) and ($json_fields->{error}->{code} =~ /^4.*/) )
        {
        print "INFO: keystone reports: ".$json_fields->{error}->{message}."\n";
        $os_info->{project}->{$project_uid}->{name}='unknown';
        $os_info->{project}->{$project_uid}->{status}="NotFound - ".$json_fields->{error}->{code};
        }
    else
        {
        print $url."\n";
        print Dumper %$json_fields;
        #exit;
        }

    #foreach my $p (@{$json_fields->{projects}})
    #    {
    #    $os_info->{project}->{$p->{id}}->{name}=$p->{name};
    #    $os_info->{project}->{$p->{id}}->{domain}=$p->{domain_id};
    #    $os_info->{project}->{$p->{id}}->{status}=$p->{enabled};
    #    }
    return $os_info;
    }

sub get_user2project
    {
    my $os_info=shift;
    my $user_id=shift;
    my $endpt="/v3/users/$user_id/projects";
    my $url="https://engage1.massopen.cloud:5000";
    my $resp;

    if( not (exists $os_info->{admin}->{token} ) )
        {
        my $tac=get_scoped_token($os_info->{token},$os_info->{admin}->{id});
        $os_info->{admin}->{token}=$tac->{token};
        $os_info->{admin}->{catalog}=$tac->{catalog};
        }
    $url=find_in_catalog("keystone",$os_info->{admin}->{catalog});
    $url=$url.$endpt;

    my $curl=new WWW::Curl::Easy;
    $curl->setopt(CURLOPT_URL,$url);
    $curl->setopt(WWW::Curl::Easy::CURLOPT_HTTPHEADER(),["X-Auth-Token: $os_info->{admin}->{token}"]);
    $curl->setopt(CURLOPT_WRITEDATA, \$resp);
    $curl->perform();

    my $json_fields = from_json($resp);
    #print "\n\n--new user\n\n";
    #print Dumper %$json_fields;
    foreach my $p (@{$json_fields->{projects}})
        {
        #print "$user_id, $p->{id}\n";
        $os_info->{users2projects}->{$user_id}->{$p->{id}}=1;
        }
    return $os_info;
    }

sub get_all_users
    {
    my $os_info=shift;
    my $endpt="/v3/users";
    my $url="https://engage1.massopen.cloud:5000";
    my $resp;

    if( not (exists $os_info->{admin}->{token} ) )
        {
        my $tac=get_scoped_token($os_info->{token},$os_info->{admin}->{id});
        $os_info->{admin}->{token}=$tac->{token};
        $os_info->{admin}->{catalog}=$tac->{catalog};
        }
    $url=find_in_catalog("keystone",$os_info->{admin}->{catalog});
    $url=$url.$endpt;

    my $curl=new WWW::Curl::Easy;
    $curl->setopt(CURLOPT_URL,$url);
    $curl->setopt(WWW::Curl::Easy::CURLOPT_HTTPHEADER(),["X-Auth-Token: $os_info->{admin}->{token}"]);
    $curl->setopt(CURLOPT_WRITEDATA, \$resp);
    $curl->perform();

    my $json_fields = from_json($resp);
    #print Dumper %$json_fields;
    #print "$resp\n";
    #exit;
    foreach my $p (@{$json_fields->{"users"}})
        {
        $os_info->{users}->{$p->{id}}->{domain}=$p->{domain_id};
        $os_info->{users}->{$p->{id}}->{name}=$p->{name};
        $os_info->{users}->{$p->{id}}->{email}=$p->{email};
        $os_info->{users}->{$p->{id}}->{enabled}=$p->{enabled};
        $os_info->{users}->{$p->{id}}->{default_project}=$p->{default_project};
        # $os_info->{users}->{$p->{id}}->{enabled}=$p->{};
        # $os_info->{users}->{$p->{id}}->{email}=$p->{email};

        #for each user get the list of projects
        $os_info=get_user2project($os_info,$p->{id});
        }
    return $os_info;
    }

sub get_floating_ips
    {
    my $os_info=shift;
    my $endpt="/v2.0/floatingips";
    my $url="https://engage1.massopen.cloud:9696";
    my $resp;

    if( not (exists $os_info->{admin}->{token} ) )
        {
        my $tac=get_scoped_token($os_info->{token},$os_info->{admin}->{id});
        $os_info->{admin}->{token}=$tac->{token};
        $os_info->{admin}->{catalog}=$tac->{catalog};
        }
    $url=find_in_catalog("neutron",$os_info->{admin}->{catalog});
    $url=$url.$endpt;

    my $curl=new WWW::Curl::Easy;
    $curl->setopt(CURLOPT_URL,$url);
    $curl->setopt(WWW::Curl::Easy::CURLOPT_HTTPHEADER(),["X-Auth-Token: $os_info->{admin}->{token}"]);
    $curl->setopt(CURLOPT_WRITEDATA, \$resp);
    $curl->perform();

    my $json_fields = from_json($resp);
    foreach my $p (@{$json_fields->{floatingips}})
        {
        #print "$user_id, $p->{id}\n";
        $os_info->{floating_ips}->{$p->{id}}->{floating_ip_address}=$p->{floating_ip_address};
        $os_info->{floating_ips}->{$p->{id}}->{port_id}=$p->{port_id};
        $os_info->{floating_ips}->{$p->{id}}->{fixed_ip_address}=$p->{fixed_ip_address};
        $os_info->{floating_ips}->{$p->{id}}->{project_id}=$p->{project_id};
        $os_info->{floating_ips}->{$p->{id}}->{status}=$p->{status};
        $os_info->{floating_ips}->{$p->{id}}->{router_id}=$p->{router_id};
        $os_info->{floating_ips}->{$p->{id}}->{floating_network_id}=$p->{floating_network_id};
  
        $os_info=get_add_project($os_info,$p->{project_id}); # this checks and adds a project
        #$os_info->{floating_ips}->{$p->{id}}->{}=$p->{};
        }
    #print "\n\n--------- floating ips\n";
    #print Dumper(@{$json_fields->{floatingips}});
    #print "\n\n---------  os_info\n";
    #print Dumper($os_info);
    #exit;
    return $os_info;
    }

# get all volumes

sub find_in_catalog
    {
    my $name=shift;
    my $catalog=shift;
    my $endpoint;

    #should reorganize catalog to make finding a particular service faster
    foreach my $entry (@{$catalog})
        {
        if($entry->{name} eq $name)
            {
            foreach my $endpt (@{$entry->{endpoints}})
                {
                if($endpt->{interface} eq 'public')
                    {
                    return $endpt->{url};
                    }
                }
            }
        }

    return $endpoint;
    }

sub find_region
    {
    my $name=shift;
    my $catalog=shift;
    my $region;

    #should reorganize catalog to make finding a particular service faster
    foreach my $entry (@{$catalog})
        {
        if($entry->{name} eq $name)
            {
            foreach my $endpt (@{$entry->{endpoints}})
                {
                if($endpt->{interface} eq 'public')
                    {
                    return $endpt->{'region_id'};
                    }
                }
            }
        }

    return $region;
    }

#sub add_addresses
#    {
#    my $os_info=shift;
#    my $project_id=shift;
#    my $vm_id=shift;
#    my %addresses=shift;
#
#    $os_info->{floating_ip}->
#    
#    }

sub get_vm_details
    {
    my $os_info=shift;
    my $vm_id=shift;
    if(!defined($vm_id) or length($vm_id)==0)
        {
        print STDERR "Invalid vm_id passed to get_vm_details\n";
        return ("","","");
        }
    my $endpt="/servers/$vm_id";
    my $url="";
    my $resp;

    if( not (exists $os_info->{admin}->{token} ) )
        {
        my $tac=get_scoped_token($os_info->{token},$os_info->{admin}->{id});
        $os_info->{admin}->{token}=$tac->{token};
        $os_info->{admin}->{catalog}=$tac->{catalog};
        }
    $url=find_in_catalog("nova",$os_info->{admin}->{catalog});
    $url=$url.$endpt;

    my $curl=new WWW::Curl::Easy;
    $curl->setopt(CURLOPT_URL,$url);
    $curl->setopt(WWW::Curl::Easy::CURLOPT_HTTPHEADER(),["X-Auth-Token: $os_info->{admin}->{token}"]);
    $curl->setopt(CURLOPT_WRITEDATA, \$resp);
    $curl->perform();

    #$vm_details = from_json($resp);
    print "====>>>>  \n";
    print $resp;
    #print Dumper(%$vm_details);
    exit;
    }

sub get_all_vm_details
    {
    my $os_info=shift;
    my $flavors=shift;
    my $endpt="/servers/detail?all_tenants=true";
    my $url="";
    my $resp;

    if( not (exists $os_info->{admin}->{token} ) )
        {
        my $tac=get_scoped_token($os_info->{token},$os_info->{admin}->{id});
        $os_info->{admin}->{token}=$tac->{token};
        $os_info->{admin}->{catalog}=$tac->{catalog};
        }
    $url=find_in_catalog("nova",$os_info->{admin}->{catalog});
    $url=$url.$endpt;

    my $curl=new WWW::Curl::Easy;
    $curl->setopt(CURLOPT_URL,$url);
    $curl->setopt(WWW::Curl::Easy::CURLOPT_HTTPHEADER(),["X-Auth-Token: $os_info->{admin}->{token}"]);
    $curl->setopt(CURLOPT_WRITEDATA, \$resp);
    $curl->perform();

    my $vm_details = from_json($resp);
    #print $resp;
    #print Dumper(%$vm_details);
    #exit;
    foreach my $vm (@{$vm_details->{servers}})
        {
        #print "$user_id, $vm->{id}\n";
        #print Dumper $vm;
        #exit;

        #$VAR1 = {
        #  'links' => [
        #               {
        #                 'href' => 'https://kaizen.massopen.cloud:8774/v2/344583b960c146319398dffb1d7b43b6/servers/dded8ecd-a03a-4dd1-9988-464c053eaef1',
        #                 'rel' => 'self'
        #               },
        #               {
        #                 'href' => 'https://kaizen.massopen.cloud:8774/344583b960c146319398dffb1d7b43b6/servers/dded8ecd-a03a-4dd1-9988-464c053eaef1',
        #                 'rel' => 'bookmark'
        #               }
        #             ],
        #  'OS-SRV-USG:terminated_at' => undef,
        #  'hostId' => '',
        #  'id' => 'dded8ecd-a03a-4dd1-9988-464c053eaef1',
        #  'OS-EXT-STS:task_state' => 'scheduling',
        #  'user_id' => '719dda5b42a74aceae60b9c2bcb7d6b3',
        #  'OS-EXT-SRV-ATTR:hypervisor_hostname' => undef,
        #  'updated' => '2018-10-03T22:49:09Z',
        #  'OS-EXT-SRV-ATTR:host' => undef,
        #  'image' => '',
        #  'OS-EXT-SRV-ATTR:instance_name' => '',
        #  'OS-EXT-AZ:availability_zone' => 'nova',
        #  'os-extended-volumes:volumes_attached' => [],
        #  'OS-DCF:diskConfig' => 'AUTO',
        #  'name' => 'rabbitmq',
        #  'created' => '2018-09-18T21:29:45Z',
        #  'OS-EXT-STS:power_state' => 0,
        #  'tenant_id' => '54e3468f0fd849709f2e6716f11f62cb',
        #  'accessIPv4' => '',
        #  'accessIPv6' => '',
        #  'flavor' => {
        #                'id' => '73ae9789-4fe9-4299-978c-9cb8f4964298',
        #                'links' => [
        #                             {
        #                               'href' => 'https://kaizen.massopen.cloud:8774/344583b960c146319398dffb1d7b43b6/flavors/73ae9789-4fe9-4299-978c-9cb8f4964298',
        #                               'rel' => 'bookmark'
        #                             }
        #                           ]
        #              },
        #  'progress' => 0,
        #  'config_drive' => '',
        #  'metadata' => {},
        #  'addresses' => {},
        #  'OS-SRV-USG:launched_at' => undef,
        #  'status' => 'BUILD',
        #  'OS-EXT-STS:vm_state' => 'building',
        #  'key_name' => 'vinaykns'
        #};
        # 
        # Not sure if the VM status is:
        #    'OS-EXT-STS:power_state' => 0
        #    'status' => 'BUILD'
        #    'OS-EXT-STS:vm_state' => 'building'
        #    'status' => 'BUILD'

        my $project_id=$vm->{tenant_id};
        my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
        my $ts = sprintf("%04d-%02d-%02d %02d:%02d:%02d", $year+1900, $mon+1, $mday, $hour, $min, $sec);
        if(length($vm->{project_id})>0) { $project_id=$vm->{project_id}; }
        $os_info->{project}->{$project_id}->{VM}->{$vm->{id}}->{events}->{$ts}->{user_id}=$vm->{user_id};
        $os_info->{project}->{$project_id}->{VM}->{$vm->{id}}->{events}->{$ts}->{end_ts}=$ts;
        $os_info->{project}->{$project_id}->{VM}->{$vm->{id}}->{events}->{$ts}->{state}=$vm->{status};
        $os_info->{project}->{$project_id}->{VM}->{$vm->{id}}->{events}->{$ts}->{name}=$vm->{name};
        $os_info->{project}->{$project_id}->{VM}->{$vm->{id}}->{events}->{$ts}->{flavor}=$vm->{flavor};
        $os_info->{project}->{$project_id}->{VM}->{$vm->{id}}->{events}->{$ts}->{event_type}="instant";

        if(defined($flavors->{$vm->{flavor}}) && $flavors->{$vm->{flavor}}->{vcpus}>0)
            {
            # First try to get it from the flavor - in the case of resizing, this doesn't always work.
            $os_info->{project}->{$project_id}->{VM}->{$vm->{id}}->{events}->{$ts}->{vcpus}=$flavors->{$vm->{flavor}}->{vcpus};
            $os_info->{project}->{$project_id}->{VM}->{$vm->{id}}->{events}->{$ts}->{mem}=$flavors->{$vm->{flavor}}->{ram}/1024;
            $os_info->{project}->{$project_id}->{VM}->{$vm->{id}}->{events}->{$ts}->{disk_gb}=$flavors->{$vm->{flavor}}->{disk};
            }
        else
            {
            #my ($vcpu, $ram, $disk) =get_vm_details($os_info,$vm->{id});
            }
        #need to get the floating ip addresses done first
        #maybe need to get the networks/subnets done first 
        # example of address:
        #     'addresses' => {
        #         'mosaic_network' => [
        #             {
        #             'OS-EXT-IPS-MAC:mac_addr' => 'fa:16:3e:6e:f9:60',
        #             'OS-EXT-IPS:type' => 'fixed',
        #             'version' => 4,
        #             'addr' => '192.168.0.4'
        #             },
        #             {
        #             'OS-EXT-IPS-MAC:mac_addr' => 'fa:16:3e:6e:f9:60',
        #             'OS-EXT-IPS:type' => 'floating',
        #             'version' => 4,
        #             'addr' => '128.31.22.24'
        #             }
        #         ]
        #     }
        #$os_info = add_networks($os_info, $project_id, $vm->{id}, $vm->{addresses});
        
        }
    return $os_info;
    }

#  use panko this to find the instances.
#  This needs to be stored in a dababase.
sub get_panko_data
    {
    my $os_info=shift;
    my $endpt=find_in_catalog("panko",$os_info->{admin}->{catalog});
    my $query_string='?q.field=all_tenants&q.op=eq&q.value=True';
    my $url = $endpt."/v2/events".$query_string;
    
    if(length($endpt) < 1) 
        { 
        print "WARNING: Panko is not in catalog - continueing\n";
        return $os_info; 
        }
    #print "panko endpt = '$endpt'\n";
    # print "URL: $url\n";
    my $curl=new WWW::Curl::Easy;
    my $resp;
    $curl->setopt(CURLOPT_URL,$url);
    $curl->setopt(WWW::Curl::Easy::CURLOPT_HTTPHEADER(),["X-Auth-Token: $os_info->{admin}->{token}"]);
    $curl->setopt(CURLOPT_WRITEDATA, \$resp);
    $curl->perform();

    #print "\n\n".$resp."\n\n";

    my $fields=from_json $resp;
    my $rec;
    for my $event (@$fields)
        {
        if($event->{event_type}=~/compute\.instance/)
            {
            $rec=undef;
            $rec->{event_type}=$event->{event_type};
            # print Dumper $event;
            foreach my $trait (@{$event->{traits}})
                {
                if   ($trait->{name} eq  'project_id')             { $rec->{project_id}  = $trait->{value}; }
                elsif($trait->{name} eq  'instance_id')            { $rec->{instance_id} = $trait->{value}; }
                elsif($trait->{name} eq  'audit_period_beginning') { $rec->{start_ts}    = $trait->{value}; }
                elsif($trait->{name} eq  'audit_period_ending')    { $rec->{end_ts}      = $trait->{value}; }
                elsif($trait->{name} eq  'state')                  { $rec->{state}       = $trait->{value}; }
                elsif($trait->{name} eq  'instance_type')          { $rec->{flavor}      = $trait->{value}; }
                elsif($trait->{name} eq  'vcpus')                  { $rec->{vcpus}       = $trait->{value}; }
                elsif($trait->{name} eq  'memory_mb')              { $rec->{mem}         = $trait->{value}; }
                elsif($trait->{name} eq  'disk_gb')                { $rec->{disk_gb}     = $trait->{value}; }
                }
            $os_info->{project}->{$rec->{project_id}}->{vm_cnt}=1;
            $os_info->{project}->{$rec->{project_id}}->{VM}->{$rec->{instance_id}}->{event_cnt}=1;

            $os_info->{project}->{$rec->{project_id}}->{VM}->{$rec->{instance_id}}->{events}->{$rec->{start_ts}}->{end_ts}=$rec->{end_ts};
            $os_info->{project}->{$rec->{project_id}}->{VM}->{$rec->{instance_id}}->{events}->{$rec->{start_ts}}->{state}=$rec->{state};
            $os_info->{project}->{$rec->{project_id}}->{VM}->{$rec->{instance_id}}->{events}->{$rec->{start_ts}}->{flavor}=$rec->{flavor};
            $os_info->{project}->{$rec->{project_id}}->{VM}->{$rec->{instance_id}}->{events}->{$rec->{start_ts}}->{vcpus}=$rec->{vcpus};
            $os_info->{project}->{$rec->{project_id}}->{VM}->{$rec->{instance_id}}->{events}->{$rec->{start_ts}}->{mem}=$rec->{mem}/1024;
            $os_info->{project}->{$rec->{project_id}}->{VM}->{$rec->{instance_id}}->{events}->{$rec->{start_ts}}->{disk_gb}=$rec->{disk_gb};
            $os_info->{project}->{$rec->{project_id}}->{VM}->{$rec->{instance_id}}->{events}->{$rec->{start_ts}}->{event_type}=$rec->{event_type};
            }
        else 
            {
            print STDERR "---> Unhandeled event: $event->{event_type}\n";
            }    
        }
    #print Dumper{@$fields};
    #print Dumper{%$os_info};
    #exit;
    return $os_info;
    }

sub get_volumes_from_panko
    {
    my $os_info=shift;

    return $os_info;
    }

sub get_volumes_from_cinderV3
    {
    my $os_info=shift;
    my $url='';
    my $endpt = "/volumes/detail?all_tenants=1";

    if( not (exists $os_info->{admin}->{token} ) )
        {
        my $tac=get_scoped_token($os_info->{token},$os_info->{admin}->{id});
        $os_info->{admin}->{token}=$tac->{token};
        $os_info->{admin}->{catalog}=$tac->{catalog};
        }
    $url=find_in_catalog("cinderv3",$os_info->{admin}->{catalog});
    if(length($url) == 0) { return $os_info; }

    # $url should be something of the form
    #
    #    address                       :port/ version / admin uuid
    #    https://engage1.massopen.cloud:8776/v3/c53c18b2d29641e0877bbbd8d87f8267
        
    $url=$url.$endpt;

    #print "$url\n\n\n";
    #print Dumper $os_info;
    #exit;

    my $curl=new WWW::Curl::Easy;
    my $resp;
    $curl->setopt(CURLOPT_URL,$url);
    $curl->setopt(WWW::Curl::Easy::CURLOPT_HTTPHEADER(),["X-Auth-Token: $os_info->{admin}->{token}"]);
    $curl->setopt(CURLOPT_WRITEDATA, \$resp);
    $curl->perform();

    my $fields=from_json $resp;
    foreach my $v (@{$fields->{volumes}})
        {
        my $project_uid=$v->{'os-vol-tenant-attr:tenant_id'};
        my $volume_uid=$v->{'id'};

        $os_info->{project}->{$project_uid}->{Vol}->{$volume_uid}->{status}=$v->{status};
        $os_info->{project}->{$project_uid}->{Vol}->{$volume_uid}->{size}=$v->{size};

        foreach my $i (@{$v->{attachments}})
            {
            my $attachment_id = $v->{attachment_id};
            $os_info->{item_ts2item_ts}->{$attachment_id}->{type} = "vm-disk";
            $os_info->{item_ts2item_ts}->{$attachment_id}->{project} = $project_uid;
            $os_info->{item_ts2item_ts}->{$attachment_id}->{id1} = $i->{server_id};
            $os_info->{item_ts2item_ts}->{$attachment_id}->{id2} = $volume_uid;
            }
        }
    return $os_info;
    }


sub login_to_admin_acct
    {
    my $os_info=shift;

    return $os_info;
    }

sub get_region_id
    {
    my $conn=shift;
    my $region=shift;

    my $sth = $conn->prepare("select domain_id from domain where domain_name=?");
    $sth->execute($region);
    if($sth->rows==0)
        {
        my $sth2=$conn->prepare("insert into domain (domain_name,domain_uid) values (?,null)");
        $sth2->execute($region);
        }
    $sth->execute($region);
    if(length($sth->errstr)>0)
        {
        print $sth->errstr."\n";
        exit();
        }
    my $region_id=$sth->fetchrow_arrayref()->[0];

    return $region_id;
    }

sub get_item_type_id
    {
    my $conn=shift;
    my $item_desc=shift;
    my $get_item_type_id_sth=$conn->prepare("select item_type_id from item_type where item_definition=?");

    $get_item_type_id_sth->execute($item_desc);
    if($get_item_type_id_sth->rows==0)
        {
        my $ins=$conn->prepare("insert into item_type (item_definition,item_desc) values (?,null)");
        $ins->execute($item_desc);
        $get_item_type_id_sth->execute($item_desc);
        }
    $get_item_type_id_sth->execute($item_desc);

    if(length($get_item_type_id_sth->errstr)>0)
        {
        print $get_item_type_id_sth->errstr."\n";
        exit();
        }
    my $item_type_id=$get_item_type_id_sth->fetchrow_arrayref()->[0];

    return $item_type_id;
    }

sub get_poc_id
    {
    my $conn=shift;      # req
    my $region_id=shift; # req
    my $uid=shift;       # opt - required to add a user
    my $name=shift;      # opt - required to add a user
    my $email=shift;     # opt - required to add a user

    my $poc_id=undef;

    my $get_poc_sth=$conn->prepare("select poc_id from poc where domain_id=? and user_uid=?");
    $get_poc_sth->execute($region_id,$uid);
    if($get_poc_sth->rows==0 and length($uid)>0 and length($name)>0)
        {
        my $ins=$conn->prepare("insert into poc (domain_id,user_uid, username, email) values (?,?,?,?)");
        $ins->execute($region_id,$uid,$name,$email);
        if(length($ins->errstr)>0)
            {
            print $ins->errstr."\n";
            exit();
            }
        $get_poc_sth->execute($region_id,$uid);
        }
    $poc_id=$get_poc_sth->fetchrow_arrayref()->[0];
    return $poc_id;
    }

sub get_project_id
    {
    my $conn=shift;
    my $region_id=shift;
    my $uid=shift;
    my $name=shift;
    my $project_id;

    my $sth=$conn->prepare("select project_id from project where domain_id=? and project_uid=?");
    $sth->execute($region_id,$uid);
    if($sth->rows==0 and length($name)>0)
        {
        my $ins=$conn->prepare("insert into project (domain_id, project_uid, project_name) values (?,?,?)");
        $ins->execute($region_id,$uid,$name);
        
        if(length($sth->errstr)>0)
            {
            print $sth->errstr."\n";
            exit();
            }
        $sth->execute($region_id,$uid);
        if(length($sth->errstr)>0) 
            {
            print $sth->errstr."\n";
            exit();
            }
        }
    $project_id=$sth->fetchrow_arrayref()->[0];
    return $project_id;
    }

sub get_item_id
    {
    my $conn=shift;
    my $region_id=shift;
    my $project_id=shift;
    my $item_uid=shift;
    my $item_name=shift;
    my $item_type_id=shift;

    my $item_id=undef;
    my $get_item_id_sth=undef;

    if(defined $item_type_id )
        {
        $get_item_id_sth=$conn->prepare("select item_id from item where domain_id=? and project_id=? and item_type_id=? and item_uid=?");
        $get_item_id_sth->execute($region_id,$project_id,$item_type_id,$item_uid);
        if($get_item_id_sth->rows==0)
            {
            my $ins=$conn->prepare("insert into item (domain_id,project_id,item_type_id,item_uid,item_name) values (?,?,?,?,?)");
            $ins->execute($region_id,$project_id,$item_type_id,$item_uid,$item_name);
            }
        $get_item_id_sth->execute($region_id,$project_id,$item_type_id,$item_uid);
        }
    else
        {
        $get_item_id_sth=$conn->prepare("select item_id from item where domain_id=? and project_id=? and item_uid=?");
        $get_item_id_sth->execute($region_id,$project_id,$item_uid);
        }

    if(length($get_item_id_sth->errstr)>0)
        {
        print $get_item_id_sth->errstr."\n";
        exit();
        }
    my $item_id=$get_item_id_sth->fetchrow_arrayref()->[0];

    return $item_id;
    }

sub get_item_ts_id
    {
    my $conn=shift;
    my $region_id=shift;
    my $project_id=shift;
    my $item_type_id=shift;
    my $item_id=shift;
    my $start_ts=shift; 
    my $end_ts=shift;
    my $state=shift;
    my $size=shift;
    my $item_ts;

    my $get_item_ts_id_sth;
    if(defined($item_type_id))
        {
        $get_item_ts_id_sth=$conn->prepare("select * from item_ts where domain_id=? and project_id=? and item_type_id=? and item_id=? and start_ts=?");
        $get_item_ts_id_sth->execute($region_id,$project_id,$item_type_id,$item_id,$start_ts);
        if( $get_item_ts_id_sth->rows==0 )
            {
            my $ins=$conn->prepare("insert into item_ts (domain_id,project_id,item_type_id,item_id,start_ts,end_ts,state,item_size) values (?,?,?,?,?,?,?,?)");
            $ins->execute($region_id,$project_id,$item_type_id,$item_id,$start_ts,$end_ts,$state,$size);
            }
        }
    else
        {
        # this will be a gocha - but in this case we don't have the information to perform the insert (we don't know the item_type)
        # However, in the mapping of items to items at a given timestam, we need to look up both records in the item_ts table.
        $get_item_ts_id_sth=$conn->prepare("select * from item_ts where domain_id=? and project_id=? and item_id=? and start_ts=?");
        $get_item_ts_id_sth->execute($region_id,$project_id,$item_id,$start_ts);
        }        
    return $item_ts;
    }

sub get_timestamp
    {
    my $conn=shift;

    my $get_timestamp_sth=$conn->prepare("select now()");
    $get_timestamp_sth->execute();
    return $get_timestamp_sth->fetchrow_arrayref()->[0];    
    }

sub store_users
    {
    my $conn=shift;
    my $users=shift;
    my $region=shift;
    my $region_id=shift;
    my $timestamp=shift;

    foreach my $u (keys %{$users})
        {
        my $poc_id=get_poc_id($conn,$region_id,$u,$users->{$u}->{name},$users->{$u}->{email});
        if(!defined($poc_id)) 
            {
            print "Warning: unable to add user $u, $users->{$u}->{name}, $users->{$u}->{email} to region: $region \n";
            }
        }        
    }

sub store_billing_info
    {
    my $conn=shift;
    my $os_data=shift;
    #fist locate the region
    my $region=find_region("keystone",$os_data->{'admin'}->{'catalog'});
    my $region_id=undef;
    my $timestamp=get_timestamp($conn);
    print "timestamp=$timestamp\n";
    print "region=$region\n";

    if(length($region)>0)
        {
        $region_id=get_region_id($conn,$region);
        }
    #print "region_id=$region_id\n";
    if($region_id)
        {
        #my $get_poc_sth=$conn->prepare("select poc_id from poc where domain_id=? and user_uid=?");

        #add users
        store_users($conn,$os_data->{users},$region,$region_id,$timestamp);
        #foreach my $u (keys %{$os_data->{users}})
        #    {
        #    my $poc_id=get_poc_id($conn,$region_id,$u,$os_data->{users}->{$u}->{name},$os_data->{users}->{$u}->{email});
        #    if(!defined($poc_id)) 
        #        {
        #        print "Warning: unable to add user $u, $os_data->{users}->{$u}->{name}, $os_data->{users}->{$u}->{email} to region: $region \n";
        #        }
        #    }

        #add projects
        store_projects($conn,$os_data->{projects},$region,$region_id,$timestamp);
        foreach my $p (keys %{$os_data->{'project'}})
            {
            my $project_id = get_project_id($conn,$region_id,$p,$os_data->{'project'}->{$p}->{'name'});
            print "project_id: $project_id\n";
            if($project_id)
                {
                my $get_item_id_sth=$conn->prepare("select item_id from item where domain_id=? and project_id=? and item_type_id=? and item_uid=?");
                foreach my $v (keys %{$os_data->{'project'}->{$p}->{'Vol'}})
                    {
                    print "    item(Vol): $v\n";
                    my $item_type_id=get_item_type_id($conn,"Vol");
                    my $item_id=   get_item_id(   $conn,$region_id,$project_id,$v,   $os_data->{project}->{$p}->{'Vol'}->{$v}->{name},$item_type_id);
                    my $item_ts_id=get_item_ts_id($conn,$region_id,$project_id,$item_type_id,$item_id, $timestamp,undef,'  ',$os_data->{project}->{$p}->{'Vol'}->{$v}->{size});
                    print "    item_type_id: $item_type_id\n"; 
                    }
                foreach my $i (keys %{$os_data->{'project'}->{$p}->{'VM'}})
                    {
                    print "    item(VM): $i\n";
                    foreach my $e (keys %{$os_data->{project}->{$p}->{'VM'}->{$i}->{'events'}})
                        {
                        my $evt=$os_data->{project}->{$p}->{'VM'}->{$i}->{'events'}->{$e};
                        my $item_desc='VM('.$evt->{'vcpus'}.','.$evt->{'mem'}.','.$evt->{'disk_gb'}.')';

                        my $item_type_id=get_item_type_id($conn,$item_desc);
                        my $item_id=get_item_id($conn,$region_id,$project_id,$item_type_id,$i,$os_data->{project}->{$p}->{'VM'}->{$i}->{name});
                        my $item_ts_id=get_item_ts_id($conn,$region_id,$project_id,$item_type_id,$item_id,$e,$evt->{'end_ts'},$evt->{'state'},undef);
                        #add the item_ts if needed
                        #$get_item_ts_id_sth->execute($region_id,$project_id,$item_type_id,$item_id,$e);
                        #if($get_item_ts_id_sth->rows==0)
                        #    {
                        #    my $ins=$conn->prepare("insert into item_ts (domain_id,project_id,item_type_id,item_id,start_ts,end_ts,state) values (?,?,?,?,?,?,?)");
                        #    $ins->execute($region_id,$project_id,$item_type_id,$item_id,$e,$evt->{'end_ts'},$evt->{'state'});
                        #    }
                        }
                    }
                }
            }
    
        #map users to projects
        my $get_project_id=$conn->prepare("select project_id from project where domain_id=? and project_uid=?");
        my $get_project2poc=$conn->prepare("select project_id,poc_id from project2poc where domain_id=? and project_id=? and poc_id=?");
        foreach my $user (keys %{$os_data->{users2projects}})
            {
            my $poc_id=get_poc_id($conn,$region_id,$user);
            #print "POC_ID: $poc_id\n";
            if( !defined($poc_id) )
                {
                print "WARNING: cannot find userid from uuid:$user --> $poc_id\n";
                }
            else
                {
                foreach my $proj (keys %{$os_data->{users2projects}->{$user}})
                    {
                    $get_project_id->execute($region_id,$proj);
                    if($get_project_id->rows==0)
                        {
                        print "WARNING cannot find project id from uuid:$proj\n";
                        }
                    else
                        {
                        my $project_id=$get_project_id->fetchrow_arrayref()->[0];
                        $get_project2poc->execute($region_id,$project_id,$poc_id);
                        if($get_project2poc->rows==0)
                            {
                            my $ins=$conn->prepare("insert into project2poc (domain_id,project_id,poc_id) values (?,?,?)");
                            $ins->execute($region_id,$project_id,$poc_id);
                            if(length($ins->errstr)>0)
                                {
                                print "ERROR: $ins->errstr\n";
                                }
                            }
                        }
                    }
                } 
            }
    
        
        # Add floating ips
        my $get_floating_ip_type_id=$conn->prepare("select item_type_id from item_type where item_definition='floating_ip'");
        my $get_floating_ip_id=$conn->prepare("select item_id from item where domain_id=? and project_id=(select project_id from project where domain_id=? and project_uid=?) and item_type_id=? and item_uid=?"); 
        foreach my $fip (keys %{$os_data->{floating_ips}})
            {
            $get_floating_ip_type_id->execute();
            if($get_floating_ip_type_id->rows==0)
                {
                my $ins=$conn->prepare("insert into item_type (item_definition,item_desc) values ('floating_ip','floating_ip')");
                $ins->execute();
                $get_floating_ip_type_id->execute();
                }
            $get_floating_ip_type_id->execute();
            if(length($get_floating_ip_type_id->errstr)>0)
                {
                print $get_floating_ip_type_id->errstr."\n";
                exit();
                }
            my $floating_ip_type_id=$get_floating_ip_type_id->fetchrow_arrayref()->[0];

            $get_floating_ip_id->execute($region_id,$region_id,$os_data->{floating_ips}->{$fip}->{'project_id'},$floating_ip_type_id,$fip);
            if($get_floating_ip_id->rows==0)
                {
                #look up project id from domain/project_id
                $get_project_id->execute($region_id,$os_data->{floating_ips}->{$fip}->{'project_id'});
                if($get_project_id->rows==0)
                    {
                    #add proejct id maybe flag as an WARNING for now.
                    print "WARNING: unable to find project id from '$os_data->{floating_ips}->{$fip}->{project_id} - $os_data->{floating_ips}->{$fip}->{status}, $os_data->{floating_ips}->{$fip}->{floating_ip_address} -> $os_data->{floating_ips}->{$fip}->{fixed_ip_address} $os_data->{floating_ips}->{$fip}->{port_id}\n";
                    }
                else
                    {
                    my $project_id=$get_project_id->fetchrow_arrayref()->[0]; 
                    my $state=$os_data->{floating_ips}->{$fip}->{'project_id'};
                    my $name=$os_data->{floating_ips}->{$fip}->{floating_ip_address}.' -> '.$os_data->{floating_ips}->{$fip}->{fixed_ip_address};
                    my $ins=$conn->prepare("insert into item (domain_id,project_id,item_type_id,item_uid,item_name) values (?,?,?,?,?)");
                    #print "domain_id=$region_id, proejct_id=$project_id, fip_type_id=$floating_ip_type_id,  itme_uuid=$fip, item_name=$name\n";
                    $ins->execute($region_id,$project_id,$floating_ip_type_id,$fip,$name);
                    }
                }
            else
                {
                #print "INFO: '$os_data->{floating_ips}->{$fip}->{project_id} - $os_data->{floating_ips}->{$fip}->{status}, $os_data->{floating_ips}->{$fip}->{floating_ip_address} -> $os_data->{floating_ips}->{$fip}->{fixed_ip_address} $os_data->{floating_ips}->{$fip}->{port_id}\n";
                }
            $get_floating_ip_id->execute($region_id,$region_id,$os_data->{floating_ips}->{$fip}->{'project_id'},$floating_ip_type_id,$fip);
            if(length($get_floating_ip_type_id->errstr)>0)
                {
                print $get_floating_ip_type_id->errstr."\n";
                exit();
                }
            }
        
#        #add mappings from item_ts 2 item_ts
#        foreach my $i2i (keys %{$os_data->{item_ts2item_ts}})
#            {
#            my $item_id1 = get_item_id($conn, $region_id,$project, $item_uuid);
#            my $item_id2 = get_item_id($conn, $region_id,$porject, $item_uuid);
#            my ($end_ts1)=get_end_time($conn, $region_id, $project_id, $item_id1, $start_ts )
#            my ($end_ts2)=get_end_time($conn, $region_id, $project_id, $item_id1, $start_ts )
#            my $ins=$conn->prepare("insert into item_ts2item_ts (domain_id,project_id,item_id1,start_ts1,end_ts1,item_id2,start_ts2,end_ts2) values (?,?,?,?,?,?,?,?)");
#            #print "domain_id=$region_id, proejct_id=$project_id, fip_type_id=$floating_ip_type_id,  itme_uuid=$fip, item_name=$name\n";
#            $ins->execute($region_id,$project_id,$item_id1,$start_ts1,$end_ts1,$item_id2,$start_ts2,$end_ts2);
#            }
        }
    }


my $done=0;
my $os_info;
my $n=0;
while( !$done )
    {
    my ($type, $auth_url, $user,$pass,$pg_user,$pg_pass)=get_cred(".bills.cred", $n);
    if(length($user)>0)
        {
        if($type eq 'stack')
            {
            print "0 --> OpenStack Authenticate\n";
            $os_info=get_unscoped_token($auth_url,$user,$pass);

            print "1 --> OpenStack get projects and login to to Admin \n";
            $os_info=get_os_projects($auth_url,$os_info);
            my $tac=get_scoped_token($auth_url,$os_info->{token},$os_info->{admin}->{id});
            $os_info->{admin}->{token}=$tac->{token};
            $os_info->{admin}->{catalog}=$tac->{catalog};

            print "2 --> OpenStack get all project info\n";
            $os_info=get_all_projects($os_info);

#print "A-->\n\n";
#print Dumper{%$os_info};  
#exit

            print "3 --> get all users";
            $os_info=get_all_users($os_info);

            print "3 --> OpenStack get flavors \n";
            my $flavors=get_os_flavors($os_info);
            print Dumper $flavors;

            print "4 --> OpenStack get router, networks, subnets, floating_ips\n";
            #$os_info = get_neutron_info($os_info);
            $os_info=get_floating_ips($os_info);

            print "5 --> OpenStack get instances\n";
            $os_info = get_all_vm_details($os_info, $flavors);

            print "5.2 --> OpenStack get cinder data\n";
            $os_info=get_volumes_from_cinderV3($os_info);
            #$os_info=get_volumes_from_cinderV2($os_info);

            print "6 --> OpenStack get data from panko\n";
            $os_info=get_panko_data($os_info);

            print "7 --> OpenStack store data into database\n";
            print Dumper{%$os_info};

            my $conn=get_conn($pg_user,$pg_pass);

            store_billing_info($conn,$os_info);
            del_conn($conn);
            }
        $os_info=undef;
        }
    else
        {
        $done=1;
        }
    $n=$n+1;
    }
exit;


print "A-->\n\n";
print Dumper{%$os_info}; 
exit;

