use YAML::XS;
use Parse::CSV;
use JSON;
use Data::Dumper;
use Time::Local;
use Time::Piece;
use Date::Parse;
use WWW::Curl::Easy;
use WWW::Curl::Multi;
use DBI;
use POSIX;
use strict;

# --- move to bill.pm ----
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

#  ---- end of bill.pm ----

# $data->{start_date}
#      ->{end_date}
#      ->{projects}->{users}->{}
#                  ->{uuids}->{project_name}
#                           ->{VMs}->{uuids}->{vm_name}
#                                           ->{vm_type}
#                                           ->{vm_events}->{start_time}->{status}
#                                                                      ->

sub get_active_project
    {
    my $conn=shift;
    my $data=shift;
    # need to add active dates to projects
    my $start_time=shift;
    my $end_time=shift;
    my $domain=shift;    #optional
    my $project=shift;   #optional
   
    my $sth;
    $data->{start_time}=$start_time;
    $data->{end_time}=$end_time;

    #if(defined($domain and length($domain) and defined($project) and length($project)>0)
    #    {     
    #    $sth=$conn->prepare("select project.domain_id, project.project_id, domain.domain_name, project.project_name, project.project_uid from project,domain where project.domain_id=domain.domain_id and project.project_uid=$project order by domain.domain_name, project.project_name");
    #    $sth->execute($project); #in the future add the start date and end date
    #    }
    #else
    #    {
        $sth=$conn->prepare("select project.domain_id, project.project_id, domain.domain_name, domain.domain_uid,  project.project_name, project.project_uid from project,domain where project.domain_id=domain.domain_id order by domain.domain_name, project.project_name");
        $sth->execute(); #in the future add the start date and end date
    #    }
    #handle errors

    #if there are more than 0 rows
    if($sth->rows>0)
        {
        my $row;
        while ( $row=$sth->fetchrow_hashref() )
            {
            $data->{project}->{$row->{domain_id}}->{$row->{project_id}}->{domain_name}=$row->{domain_name};
            $data->{project}->{$row->{domain_id}}->{$row->{project_id}}->{domain_uid}=$row->{domain_uid};
            $data->{project}->{$row->{domain_id}}->{$row->{project_id}}->{project_name}=$row->{project_name};
            $data->{project}->{$row->{domain_id}}->{$row->{project_id}}->{project_uid}=$row->{project_uid};
            }
        }
    return $data;
    }

sub get_hader_data
    {
    my $conn=shift;
    my $data=shift;

     #select poc.first_name, poc.last_name, poc.username, poc.email from poc, project2poc where poc_id=project2poc.poc_id and poc.domain_id=project2poc.domain_id and poc.project_id=project2poc.project_id and poc.domain_id=?

    return $data;
    }

sub get_os_vm_data
    {
    my $conn=shift;
    my $data=shift;

    my $start_time=$data->{start_time};
    my $end_time=$data->{end_time};

    # For vms, there is a start_ts and an end_ts.
    # I expect to merge records together if the start_ts == the end_ts of the next record and nothing changes
    #
    # For now, only charge for 
    my $sth=$conn->prepare('select item_type.item_definition, item.*, item_ts.item_size, item_ts.state, item_ts.start_ts, item_ts.end_ts '
                            .'from item, item_type, item_ts '
                           .'where item.domain_id=? '
                             .'and item.project_id=? '
                             .'and item.item_type_id=item_type.item_type_id '
                             .'and item.domain_id=item_ts.domain_id '
                             .'and item.project_id=item_ts.project_id '
                             .'and item.item_id=item_ts.item_id '
                             .'and item_type.item_definition like \'VM%\' '
                             .'and to_timestamp(?,\'YYYY-MM-DD HH24:MI:SS\') < item_ts.start_ts '
                             .'and item_ts.start_ts < to_timestamp(?,\'YYYY-MM-DD HH24:MI:SS\') '
                           .'order by item.item_id,item_ts.item_type_id,item_ts.start_ts' );
    foreach my $domain_id (keys %{$data->{project}} )
        {
        print "$domain_id \n";
        foreach my $project_id (keys %{$data->{project}->{$domain_id}})
            {
            #print "$project_id \n";
            #print "$start_time, $end_time \n";
            $sth->execute($domain_id, $project_id, $start_time, $end_time);
            my $item_id;
            my $gb_hours=1;
            my $prev_row;
            my $start_ts;  # Go from the start ts
            my $end_ts;    # To the end ts.
            my $cnt=0;
            my $row=undef;
            my $total_time=0.0;

            $prev_row=$sth->fetchrow_hashref(); # prime the pump

            # Have to do this convoluded time keeping as panko has a start time and an end timestamp for each record
            # But we are just probing kaizen to see if things are there (there is no panko).
            # Who knows if panko will be there in the future.

            $prev_row->{start_ts} =~ /[^.]+/;  my $t1=$&;
            $prev_row->{end_ts}   =~ /[^.]+/;  my $t2=$&; 
            $start_ts=Time::Piece->strptime($t1=>'%Y-%m-%d %H:%M:%S');
            $end_ts=Time::Piece->strptime($t1=>'%Y-%m-%d %H:%M:%S');
        
            #$total_time+=(Time::Piece->strptime($t2=>'%Y-%m-%d %H:%M:%S')-Time::Piece->strptime($t1=>'%Y-%m-%d %H:%M:%S'))/3600; # in hours
            if(defined($prev_row) && defined($prev_row->{start_ts}) && length($prev_row->{start_ts})>0)
                {
                while($row=$sth->fetchrow_hashref()) 
                    {
                    $row->{start_ts} =~ /[^.]+/;  my $t1=$&; my $ts_1=Time::Piece->strptime($t1=>'%Y-%m-%d %H:%M:%S');
                    $row->{end_ts}   =~ /[^.]+/;  my $t2=$&; my $ts_2=Time::Piece->strptime($t2=>'%Y-%m-%d %H:%M:%S');

                    #$total_time += (Time::Piece->strptime($t2=>'%Y-%m-%d %H:%M:%S')-Time::Piece->strptime($t1=>'%Y-%m-%d %H:%M:%S'))/3600; # in hours
                    #print Dumper $row;
                    #exit;
                    if($prev_row->{item_id} eq $row->{item_id} and $prev_row->{item_uid} eq $row->{item_uid} and $prev_row->{item_definition} eq $row->{item_definition})
                        {
                        if   ($ts_1 < $start_ts) { $start_ts=$ts_1; }
                        elsif($end_ts < $ts_1)   { $end_ts=$ts_1; }

                        if($end_ts < $ts_2) { $end_ts=$ts_2; }
                        }
                    else
                        {
                        #create line item in $data
                        my $time;
                        
                        $data->{project}->{$prev_row->{domain_id}}->{$prev_row->{project_id}}->{VM}->{$prev_row->{item_id}}->{$cnt}->{vm_uid}=$prev_row->{item_uid};
                        $data->{project}->{$prev_row->{domain_id}}->{$prev_row->{project_id}}->{VM}->{$prev_row->{item_id}}->{$cnt}->{vm_size}=$prev_row->{item_definition};
                        $data->{project}->{$prev_row->{domain_id}}->{$prev_row->{project_id}}->{VM}->{$prev_row->{item_id}}->{$cnt}->{vm_hours}=($end_ts-$start_ts)/3600;

                        $start_ts=$ts_1;
                        $end_ts=$ts_2;

                        $cnt=$cnt+1;
                        }

                    $prev_row=$row;
                    }
               if(defined($prev_row))  
                    {
                    #create line item in $data
                    my $total_time;
  
                    $data->{project}->{$prev_row->{domain_id}}->{$prev_row->{project_id}}->{VM}->{$prev_row->{item_id}}->{$cnt}->{vm_uid}=$prev_row->{item_uid};
                    $data->{project}->{$prev_row->{domain_id}}->{$prev_row->{project_id}}->{VM}->{$prev_row->{item_id}}->{$cnt}->{vm_size}=$prev_row->{item_definition};
                    $data->{project}->{$prev_row->{domain_id}}->{$prev_row->{project_id}}->{VM}->{$prev_row->{item_id}}->{$cnt}->{vm_hours}=($end_ts-$start_ts)/3600;
                    $cnt=$cnt+1;
                    }
                }
            }
        } 
    return $data;
    }

sub get_os_vol_data
    {
    my $conn=shift;
    my $data=shift;

    my $start_time=$data->{start_time};
    my $end_time=$data->{end_time};

    # For disks, there is only a start_ts, not an end_ts.
    # this will eventually change as we merge records together.
    my $sth=$conn->prepare('select item_type.item_definition, item.*, item_ts.item_size, item_ts.state, item_ts.start_ts, item_ts.end_ts '
                            .'from item, item_type, item_ts '
                           .'where item.domain_id=? '
                             .'and item.project_id=? '
                             .'and item.item_type_id=item_type.item_type_id '
                             .'and item.domain_id=item_ts.domain_id '
                             .'and item.project_id=item_ts.project_id '
                             .'and item.item_id=item_ts.item_id '
                             .'and item_type.item_definition like \'Vol\' '
                             .'and to_timestamp(?,\'YYYY-MM-DD HH24:MI:SS\') < item_ts.start_ts '
                             .'and item_ts.start_ts < to_timestamp(?,\'YYYY-MM-DD HH24:MI:SS\') '
                           .'order by item_type_id,item.item_id,item_ts.start_ts' );
    foreach my $domain_id (keys %{$data->{project}} )
        {
        print "$domain_id \n";
        foreach my $project_id (keys %{$data->{project}->{$domain_id}})
            {
            #print "$project_id \n";
            #print "$start_time, $end_time \n";
            $sth->execute($domain_id, $project_id, $start_time, $end_time);
            my $item_id;
            my $gb_hours=1;
            my $prev_row;
            my $start_ts;
            my $cnt=0;
            my $row=undef;
            $prev_row=$sth->fetchrow_hashref(); # prime the pump
            if(defined($prev_row) && defined($prev_row->{start_ts}) && length($prev_row->{start_ts})>0)
                {
                $start_ts=$prev_row->{start_ts};
                while($row=$sth->fetchrow_hashref()) 
                    {
                    if($prev_row->{item_id} eq $row->{item_id} and $prev_row->{item_uid} eq $row->{item_uid} and $prev_row->{item_size} eq $row->{item_size})
                        {
                        # go on to next row
                        }
                    else
                        {
                        #create line item in $data
                        my $total_time;

                        $start_time =~ /[^.]+/;          my $t1=$&;
                        $prev_row->{start_ts}=~/[^.]+/;  my $t2=$&; 
                        $total_time=(Time::Piece->strptime($t2=>'%Y-%m-%d %H:%M:%S')-Time::Piece->strptime($t1=>'%Y-%m-%d %H:%M:%S'))/3600; # in hours
                        $data->{project}->{$prev_row->{domain_id}}->{$prev_row->{project_id}}->{Vol}->{$prev_row->{item_id}}->{$cnt}->{volume_name}=$prev_row->{item_name};
                        $data->{project}->{$prev_row->{domain_id}}->{$prev_row->{project_id}}->{Vol}->{$prev_row->{item_id}}->{$cnt}->{volume_uid}=$prev_row->{item_uid};
                        $data->{project}->{$prev_row->{domain_id}}->{$prev_row->{project_id}}->{Vol}->{$prev_row->{item_id}}->{$cnt}->{volume_size}=$prev_row->{item_size};
                        $data->{project}->{$prev_row->{domain_id}}->{$prev_row->{project_id}}->{Vol}->{$prev_row->{item_id}}->{$cnt}->{volume_hours}=$total_time;
                        $cnt=$cnt+1;
                        }
                    
                    #print Dumper $row;
                    #exit;
                    $prev_row=$row;
                    }
               if(defined($prev_row))  
                    {
                    #create line item in $data
                    my $total_time;
  
                    $start_time =~ /[^.]+/;          my $t1=$&;
                    $prev_row->{start_ts}=~/[^.]+/;  my $t2=$&; 
                    $total_time=(Time::Piece->strptime($t2=>'%Y-%m-%d %H:%M:%S')-Time::Piece->strptime($t1=>'%Y-%m-%d %H:%M:%S'))/3600; # in hours
                    $data->{project}->{$prev_row->{domain_id}}->{$prev_row->{project_id}}->{Vol}->{$prev_row->{item_id}}->{$cnt}->{volume_uid}=$prev_row->{item_uid};
                    $data->{project}->{$prev_row->{domain_id}}->{$prev_row->{project_id}}->{Vol}->{$prev_row->{item_id}}->{$cnt}->{volume_size}=$prev_row->{item_size};
                    $data->{project}->{$prev_row->{domain_id}}->{$prev_row->{project_id}}->{Vol}->{$prev_row->{item_id}}->{$cnt}->{volume_hours}=$total_time;
                    $cnt=$cnt+1;
                    }
                }
            }
        }
    return $data;
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
    print STDERR $events->{$t}->{event_type}." ".$events->{$t}->{status}."  ".$start_time."   ".$end_time."  ".$power_on."\n";
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
        print STDERR $events->{$t}->{event_type}." ".$events->{$t}->{status}."  ".$start_time."   ".$end_time."  ".$power_on."\n";
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
    my $data = shift;
    my $proj_rpt_filename=shift;
    my $t1=$data->{start_time};
    my $t2=$data->{end_time};
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

    my $proj=$data->{project};
    foreach my $domain_id (sort keys %{$data->{project}})
        {
        foreach my $proj_id (sort keys %{$data->{project}->{$domain_id}})
            {
            $proj = $data->{project}->{$domain_id}->{$proj_id};
#print "------ ***** -----\n";
#print Dumper $data->{project}->{$domain_id}->{$proj_id}; # ->{project}->{domain_id}->{$proj_id}};
#print Dumper $proj;
#exit;
            $rpt= $rpt."\\begin{flushleft} \\textbf{\\textsc{OCX Project Report}}\\end{flushleft}\n"
                 ."\\begin{flushleft} \\textsc{  Project: $proj->{project_name} id: $proj->{project_uid} \\end{flushleft}\n"
                 ."\\flushleft{ \\textsc{     From: ".$t1."}}\n"
                 ."\\flushleft{ \\textsc{     To: ".$t2."}}\n"
                 ."\\newline\n";
            if(defined($proj->{VM}))
                {
                my $sub_rpt;

                # VM SubSection
                # ($sub_rpt, $sub_total) = vm_subsection($proj->{$proj_id}->{VM},$flav,$t1,$t2);
            
                # Vol SubSection

                # Floating IP SubSection

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




sub invoice_services
    {
    my $data;
    my $start_time;
    my $end_time;
    my $data;

    $start_time=$ARGV[0];
    $end_time=$ARGV[1];
    print "$start_time, $end_time \n";
    if( length($start_time) == 0 ) { print STDERR "ERROR: Please specify a start time\n"; exit(0); }
    if( length($end_time) == 0 ) { print STDERR "ERROR: Please specify a end time\n"; exit(0); }
    
    # make the assumption that all of the database name  database usernames and passwords are the same
    my ($type, $auth_url, $user,$pass,$pg_user,$pg_pass)=get_cred(".bills.cred", 0);
    my $conn=get_conn($pg_user,$pg_pass);

    $data=get_active_project($conn,$data,$start_time,$end_time); 
    $data=get_os_vm_data($conn,$data);
    $data=get_os_vol_data($conn,$data);
    
    #print "\n\n---- ------- ------\n\n";
    print Dumper{%$data};
    gen_project_reports($data, undef); #$proj_rpt_filename);
    }

invoice_services();


exit;

# $10/terabyte
# price for flavor

# 2 reports
#   cost at our proposed pricing
#   cost at amazon's pricing

# yes this is metric rollup
#sub read_metrics
#    {
#    }
