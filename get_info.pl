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

require 'get_csv.pl';
require 'get_openstack.pl';

# ----  move to bill.pm ---
sub get_cred
    {
    my $file=shift;
    my $creds=undef;
    my $text=undef;
    if(open(FP,$file)) { while(my $line=<FP>) { chomp($line); $text=$text.$line; } }
    print $text;
    if(defined($text)) { $creds=decode_json($text); }
    return $creds;
    }

sub get_conn
    {
    my $db_name=shift;
    my $user=shift;
    my $pass=shift;

    my $conn = DBI->connect("dbi:Pg:dbname=".$db_name,$user,$pass);
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
        print "select item_id from item where domain_id=$region_id and project_id=$project_id and item_type_id=$item_type_id and item_uid=$item_uid \n";
        $get_item_id_sth=$conn->prepare("select item_id from item where domain_id=? and project_id=? and item_type_id=? and item_uid=?");
        $get_item_id_sth->execute($region_id,$project_id,$item_type_id,$item_uid);
        if($get_item_id_sth->rows==0)
            {
            print "insert into item (domain_id,project_id,item_type_id,item_uid,item_name) values ($region_id,$project_id,$item_type_id,$item_uid,$item_name) \n";
            my $ins=$conn->prepare("insert into item (domain_id,project_id,item_type_id,item_uid,item_name) values (?,?,?,?,?)");
            if(!defined($item_name)) { $item_name=''; }
            $ins->execute($region_id,$project_id,$item_type_id,$item_uid,$item_name);
            }
        $get_item_id_sth->execute($region_id,$project_id,$item_type_id,$item_uid);
        }
    else
        {
        print "select item_id from item where domain_id=$region_id and project_id=$project_id and item_uid=$item_uid \n";
        $get_item_id_sth=$conn->prepare("select item_id from item where domain_id=? and project_id=? and item_uid=?");
        $get_item_id_sth->execute($region_id,$project_id,$item_uid);
        }

    if(length($get_item_id_sth->errstr)>0)
        {
        print $get_item_id_sth->errstr."\n";
        exit();
        }
    my $row_array_ref=$get_item_id_sth->fetchrow_arrayref();
    my $item_id=undef;
    if(defined($row_array_ref))
        {
        $item_id=$row_array_ref->[0];
        }
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

        #add projects
        #store_projects($conn,$os_data->{projects},$region,$region_id,$timestamp);
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

sub main
    {
    my $done=0;
    my $os_info;
    my $n=0;
    my $creds=get_cred("../.bills.cred");
    my $user;
    my $type;
    my $auth_url;
    my $pass;
    my $pg_user;
    my $pg_pass;

    foreach my $service (@{$creds->{services}})
        {
        print Dumper{%$service};  

        if(defined($service))
            {
            if($service->{'type'} eq 'OpenStack')
                {
                $os_info=get_openstack_info($os_info,$service);
                }
            }
        } 

    my $conn=get_conn($creds->{'database'}->{'dbname'},$creds->{'database'}->{'user'},$creds->{'database'}->{'pass'});
    store_billing_info($conn,$os_info);

    del_conn($conn);
    }

main();
exit;


#print "A-->\n\n";
#print Dumper{%$os_info}; 
#exit;

