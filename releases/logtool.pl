#!perl
BEGIN {
    push @INC,'./module';
}               
use warnings;       
use strict;
use Net::Telnet ();     
use IO::Tee;            
use FindBin qw($Bin);       
use lib $Bin;           
use Cwd;            
use File::Spec;         
use File::stat qw(:FIELDS);
use File::Copy;
use Data::Dumper;       
use Mail::Sender;       
use Getopt::Long;       
use Array::Compare;     
use Time::ParseDate;
use Time::Local;
use Archive::Zip qw( :ERROR_CODES :CONSTANTS );
use Term::ShellUI;
my %cfgfopt;                    
my (%precheckdata,%precheckcmdsoutputs);    
my (%olddata,%oldcmdsoutputs);
my (%checkdata,%checkcmdsoutputs);
my (%dotruedata,%dotruecmdsoutputs);
my (%dofalsedata,%dofalsecmdsoutputs);
my (%postcheckcmdsoutputs,%postcheckdata);
my (%options,%options_cli);         
my ($normal,$verbose,$extensive);
my ($scriptname_ori,$scriptname,$scriptname_dir,$scriptname_cfg);
$scriptname_cfg=$scriptname_dir=$scriptname_ori=$scriptname=$0; 
$scriptname=~s/\.\///;              
$scriptname=~s/(.*?)\.\w+$/$1/;         
$scriptname_cfg=~s/(.*?)\w+$/$1cfg/;        
$scriptname_dir=$scriptname;            
my ($dec_array,$dec_scalar,$dec_scalar_all,$print_test,$checkdata)=();
my $scalar_setflag;             
my $interupted=0;               
my %options_def=(
            help        => 0,
            usage       => 0,
            shell       =>0,            
            history_shell => "history_shell.txt",
            online      => 0,           
            rounds      => 1_000_000_000,   
            sleep       => 10,
            debug       => 0,
            config_file => "$scriptname_cfg",   
            log_dir     => "$scriptname_dir",   
            checklog_file   => "remotechecklog%h%t.txt",#
            cmdlog_file => "show tech.txt", 
            checkonhit_file => "checkonhit%h%t.txt", 
            timing      => "local",
            clock_cmd   => "show clock",    
            telnet_timeout  => 60,
            telnet_buffer   => 8_000_000,
            init_prompt => '/[\$%#>]\ ?$|login: $|password: $|username: $/i',
            ziplog      => 1,
            size2zip    => 10_000_000,
            sendemail   => 0,           
            smtpserver  => "smtp.sina.com.cn",  
            emailfrom   => "routermonitor <routermonitor\@sina.com>",
            emailfakefrom   => "routermonitor <routermonitor\@ericsson.com>",
            emailto     => "ericsson team <routermonitor\@sina.com>",
            emailreplyto    => "ericsson team <routermonitor\@sina.com>",
            emailsubj   => "failure report",
            emailpref   => "the issue were detected,for more info please see attachments.\n info collected at the failure point:\n\n\n",
            emailmax    => 600,
            repeat      => 1,           
            times       => 1,
        );
use constant USAGEMSG2 => << 'USAGE-END2';
remotecheck version 0.9x.
author: song ping <ping.song@ericsson.com>
bug report is welcome.
copywrite 2009
usage:
    logtool -help           
    logtool -usage          
    logtool -shell [OPTIONS]
    logtool [-online] [-offline|noonline] [-rounds ROUNDS] 
        [-sleep SECONDS] [-timing local|remote]
        [-debug 0|1|2|3] [-quiet] 
        [-ziplog] [-size2zip BYTES][-log_dir LOGDIR]
        [-configlog_file CONFIGLOGFILENAME] 
        [-checkonhit_file CHECKONHITFILENAME] 
        [-cmdlog_file CMDLOGFILENAME] [-dotrue] [-dofalse]
        [-sendemail] [-smtpserver SMTPSERVER] [-emailfrom EMAILFROM] 
        [-emailfakefrom EMAILFAKEFROM] [-emailto EMAILTO] 
        [-emailreplyto EMAILREPLYTO] 
        [-emailsubj EMAILSUBJECT] [-emailmax EMAILMAX]
        [-clock_cmd CLOCK_CMD] [-times TIMES] 
        [-prompt PROMPT] [-init_prompt INIT_PROMPT]
        [-telnet_timeout ROUNDS] [-telnet_buffer TELNET_BUFFER] 
        [-repeat] [-norepeat] [-history_shell HISTORY_SHELLFILE]
        -host HOSTNAME
USAGE-END2
use constant USAGEMSG => << 'USAGE-END';
logtool version 0.1x.
author: song ping <ping.song@ericsson.com>
bug report is welcome.
copywrite 2009
usage:
SYNTAX:
logtool [OPTIONS] -host HOSTNAME
OPTIONS:
[   
    -help       :print this usage
    -usage      :print a shorter usage
    COMMONLY USED OPTIONS:
    -shell      :enter shell mode
    -online -(host|hostname) <name>     
                :online mode switch
                :host name must exist in cfg file
    -[offline|noonline] -(cmdlog_file|cmdlog) <FILE>        
                :cmdlog_file - operation log file as input,def:show tech.txt
                :check with offline mode,mostly for test purpose only   
    -rounds <10>:run 10 rounds of commands blocks and stop,default 3
    -sleep <15>s:sleep for 15s between each rounds, def 10s
    -nosleep    :turn off sleep,continuously run checking as quick as possible
    -debug      :debug mode: 0/1/2/3, def 0
    -nodebug|quiet  :turn off debug mode,generate minimum output(same as -deb 0)
    SOME USEFULL OPTIONS:
    -(config_file|cfg) <FILE>   
            :configuration file, default: name-of-script.cfg
    -log_dir <FILE> :directory for log files, def: current dir
    -checklog_file <FILE>:log file for all checkings and outputs, 
            default: remotechecklog%h%t.txt     
    -(checkonhit_file|hit) <FILE>
                :log file that records only the round of commands 
            hitting the issue and corresponding actions taken afterward,
            default checkonhit+timestamp.txt    
    -cli_prompt <PROMT> :CLI prompt strings of remote router
    -timing <remote|local> :specify the source of timestamps
                :from local machine or from remote device
    -clock_cmd <CMD>    :specify the command used to get remote clock
                :cmd is-show clock in smartedge and a lot of other devices
    -telnet_timeout <seconds>
                :seconds before telnet session claim timeout
    -init_prompt <prompt patterns>
                :patterns used by telnet to find a match for remote prompt
    -telnet_buffer  :max. buffer for a 'big' command (like show tech)
                :8M by default
    -size2zip <BYTE>
            :maximum file size allowed before zip it (to save space)
    -history_shell
                :file name to story history shell commands
    EMAIL ALARTING OPTIONS:
    -sendemail      :send email switch,by default not send email
    -nosendemail    :not to send email
    -smtpserver     :smtpserver, def smtp.sina.com.cn
    -emailfrom      :from which emailbox, def routermonitor@sina.com
    -emailfakefrom  :fake email address, def routermonitor@ericsson.com
    -emailto        :email to, def routermonitor@sina.com
    -emailreplyto   :reply to, def routermonitor@sina.com
    -emailsubj      :email subject,default: failure report
    -emailpref      :some head words in email,
            defalt: the issue were detected,for more info ...
    -emailmax       :max charactors put in email text
    RARELY USED OPTIONS:
    -repeat [-times <2>]:repeat mode,repeat each cmd for 2 times before the next one
            :times default to 1
    -norepeat       :norepeat mode,default,execute each cmd only once
    -dotrue     :force the program to check (dotrue) batch, 
            :bypassing any (check) batch analysis, mostly for diagnostics
    -dofalse        :force the program to check (dofalse) batch, 
            :bypassing any (check) batch analysis, mostly for diagnostics
Note: 
    all <FILE> can be optionally either tagged with a timestamp and/or host name
    indicated by a %t %h ,e.g: -checklog_file mylog_%h%t.txt
]
    DISCRIPTIONS:
        this script was designed to be able to login to a remote system 
        then automatically and periodically collect informations based on command line 
        options and configuration files (by default the same name with a postfix of *.cfg)
    EXAMPLES: shell mode
    logtool.pl -shell
    EXAMPLES: CLI mode
    !!1) simplest form, completely relying on config file,
    !!which is by default based on the name of the script (but with .txt) under the same dir
    !!all outputs display on stdout
    logtool.pl -online -host router1
    logtool.pl -offline -cmdlog_file.txt -host router1
    !!2) add some options when needed
    !!will overide same option in all other sources (configuration file/environment/default values)
    logtool.pl -config_file myconf.cfg -online -host router 1
    !!3) anything goes wrong, run debug mode, and redirect outputs to a file for diagnostics
    logtool.pl -online -host router 1 -debug 3 > mydebugoutput.txt
    !!4) more complex form: define more options on CLI, 
    !!override all other sources for the same options
    logtool.pl -config_file myconfig.txt -online -host router1 
    -rounds 10 -sleep 20 -log_dir mylogdir -checklog_file singtel_vrrp%h%t.txt 
    -checkonhit_file vrrpissue%h%t.txt -repeat -times 3
    -sendemail -emailfrom fromemail@free.com -emailto youremail@ericsson.com 
    -emailfakefrom routermonitor@ericsson.com 
    INPUTS:
        a configuration file
    OUTPUTs:
        depending on debug level, it generate different amount of outputs:
    o a directory, holding all log files
    o a file named by option:checklog_file (may timestamped with localtime and/or host name)
    o     logging all CLIes and their outputs
    o a file named by option:checkonhit_file,(may timestamped with localtime and/or host name)
    o     logging only those CLI outputs when given conditions are met
    o status/progress print-out info during running
    o     def to STDOUT(screen), can be redirected to a file: > myoutputs.txt
    BUGS/SUPPORT/SUGGESTIONS:
        ping.song@ericsson.com
USAGE-END
checkoptions4cli(\%options,                     
                \%options_cli,
                \%options_def,
                \%cfgfopt);
cfgfparse2(\%cfgfopt,                           
            $options{debug});                   
$SIG{INT}=\&interuption_handler;                
my $term;
if ($options{shell}){                           
    $term = new Term::ShellUI(
        commands => get_commands(),
        history_file => "$options{history_shell}",      
    );
    print "\n(you are now running under UNIX-style shell mode)\n";
    print "Tab to complete,^C to stop \'run\',exit|quit|bye to exit\n";
    $term->prompt( sub{"$scriptname"            
                    . " [" 
                    . $term->{term}->GetHistory() 
                    . "]" 
                    . " >> " } );
    $term->run();                               
}else{                                          
    run ();                                     
}
sub run{
    my @difftime=();
    my $hits=0;                     
    clear_interuption();                        
    return unless ( checkoptions4run(\%options, 
                                    \%cfgfopt,
                                )
                    );
    chdir($Bin);                    
    $normal=$options{debug} 
        if ( $options{debug}=~/normal/ or $options{debug}=~/1/);
    $verbose=$options{debug} 
        if ($options{debug}=~/verbose/ or $options{debug}=~/2/);
    $extensive=$options{debug} 
        if ($options{debug}=~/extensive/ or $options{debug}=~/3/);
    prehandle(  \%options,
                \%cfgfopt,
                \@difftime) 
            or die "RUN: file operation problem within PREHANDLE procedure\n";  
    print "\n\nRUN: data parsing\n\n" if ($options{debug});
    my $host=$options{host};                    
    my $dseconds=$difftime[1];                  
    my $hostdataclause=$options{hostdataclause}; 
    if (exists ( $cfgfopt{"$hostdataclause"}{precheck} ) ){
        print "\nRUN: precheck configured, do prechecking...\n";
        dataparse(                              
                    \%options,
                    $cfgfopt{"$hostdataclause"}{'precheck'},
                    \%precheckcmdsoutputs,
                    \%precheckdata,
                    \@difftime);
    }                   
    audit();                                    
    if ( exists ( $cfgfopt{"$hostdataclause"}{check} ) ){   
        my $temp=-s $options{checklog_file};
        print "\nRUN: checklogfile before check stage is: $options{checklog_file} ($temp Byte)\n";
        print "\nRUN: check block configured,go check them in loop...\n";
        my ($checkstate,$checkchange,$checkfinal,$checkstate_res,$checkchange_res,$checkfinal_res)=();
        $checkstate=$cfgfopt{"$hostdataclause"}{hash}{checkstate};  
        $checkchange=$cfgfopt{"$hostdataclause"}{hash}{checkchange};    
        $checkfinal=$cfgfopt{"$hostdataclause"}{hash}{checkfinal};  
        dataparse(
                    \%options,
                    $cfgfopt{"$hostdataclause"}{'check'},
                    \%oldcmdsoutputs,
                    \%olddata,
                    \@difftime);
        $temp=-s $options{checklog_file};
        print "\nRUN: checklogfile after 1st check stage is: $options{checklog_file} ($temp Byte)\n";
        ($dec_array,$dec_scalar)=( actionparse( \%olddata,
                                                "olddata",
                                                $options{debug})
                                 )[0,1];
        my (@check_res,@dotrue_res,@dofalse_res)=();
        for(    my $round=1;
                (   ($round<=$options{rounds})  
                    &&                          
                    not $interupted             
                ); 
                $round++
           ){
            print "\n\nRUN: *******start $round(total $options{rounds}) rounds check*******\n";
            print "\n\nRUN: press Ctrl-C to interupt the loop\n";
            print "\nRUN: ===============process (check) block===============\n";
            dataparse(
                        \%options,
                        $cfgfopt{"$hostdataclause"}{'check'},
                        \%checkcmdsoutputs,
                        \%checkdata,
                        \@difftime);    
            $temp=-s $options{checklog_file};
            print "\nRUN: checklogfile after $round round check stage inside the loop is: $options{checklog_file} ($temp Byte)\n";
            cmdsoutputs_format(\%checkcmdsoutputs,\@check_res);
            my ($checkdata) =   (actionparse(   \%checkdata,
                                                "checkdata",
                                                $options{debug})
                                )[4];
            print "\nRUN: the \$checkdata we got now is:\n[\n$checkdata\n]\n" if ($extensive);
            $scalar_setflag=datacompare(\%checkdata,
                                        \%olddata,
                                        $options{debug});
            my $truefalse=rulecalc( $checkstate,
                                    $checkchange,
                                    $checkfinal,
                                    $dec_array,
                                    $dec_scalar,
                                    $scalar_setflag,
                                    $checkdata,
                                    $options{debug});
            $truefalse=$options{truefalse} if (exists $options{truefalse});
            %olddata=%checkdata;            
            if ($truefalse){            
                ++$hits;            
                my $th=	($hits==1)	?	('st'):
                    	($hits==2)	?	('nd'):
                    	($hits==3)	?	('rd'):
                    					('th');
                print "\nRUN: <=====looks we detected the issue (the ${hits}$th time) here! check dotrue commands..\n";
                if (exists($cfgfopt{"$hostdataclause"}{dotrue})){   
                    print "\nRUN: dotrue blocks configured,now check them\n";
                    dataparse(
                                \%options,
                                $cfgfopt{"$hostdataclause"}{'dotrue'},
                                \%dotruecmdsoutputs,
                                \%dotruedata,
                                \@difftime);
                    $temp=-s $options{checklog_file};
                    print "\nRUN: checklogfile after $round dotrue stage inside the loop is: $options{checklog_file} ($temp Byte)\n";
                    cmdsoutputs_format(\%dotruecmdsoutputs,\@dotrue_res);
                    log4online( \%options,
                                $options{checkonhit_fh_online},
                                \@check_res,
                                \@dotrue_res,
                                $hits,
                                $round);
                }else{      
                    print "\nRUN: <=====dotrue blocks not conigured,redo check block\n";
                }
            }else{          
                print "\nRUN: <=====nothing found/changed here...check dofalse commands\n";
                if (exists($cfgfopt{"$hostdataclause"}{dofalse})){
                    print "\nRUN: dofalse blocks configured,now check them\n";
                    dataparse(
                                \%options,
                                $cfgfopt{"$hostdataclause"}{'dofalse'},
                                \%dofalsecmdsoutputs,
                                \%dofalsedata,
                                \@difftime);
                    cmdsoutputs_format(\%dofalsecmdsoutputs,\@dofalse_res);
                }else{
                    print "\nRUN: <=====dofalse blocks not conigured,redo check block\n";
                }
            } 
            if ($options{sleep}){   
                print "\n        nRUN: sleep for $options{sleep}s at end of round($round)...\n";
                if ($hits){
                    print "\nRUN: so far the issue has been hit $hits times!\n" ;
                }else{
                    print "\nRUN: so far the issue hasn't appeared again...\n";
                }
                sleep $options{sleep};  
            }
            log4offline(    $options{checklog_fh_offline},
                            \@check_res,
                            \@dotrue_res,
                            \@dofalse_res) 
                        unless ($options{online});
            if ($options{ziplog}){
                print "\nRUN: ziplog set, checking and zip big log files...\n";
                zipbigfile(\%options,\@difftime);
            }
            my $temp=-s $options{checklog_file};
            print "\nRUN: checklogfile is now: $options{checklog_file} ($temp Byte)\n";
        } 
        if (exists($cfgfopt{"$hostdataclause"}{postcheck})){    
            print "\nRUN: postcheck configured, do postchecking...\n";
            dataparse(
                        \%options,
                        $cfgfopt{"$hostdataclause"}{'postcheck'},
                        \%postcheckcmdsoutputs,
                        \%postcheckdata,
                        \@difftime);
        }
        print "\nRUN: tear down telnet sessions...\n";
        $options{telnet_obj}->close if ($options{telnet_obj});  
    }else{      
        print "\nRUN: there is no check blocks conigured\n";
    } 
    $options{log_dir}                   =   $options{log_dir_ori};
    $options{checklog_file}     =   $options{checklog_file_ori}; 
    $options{checkonhit_file}   =   $options{checkonhit_file_ori};
    print "Prehandle: restored log_dir name base: $options{log_dir_ori}\n";     
    print "PREHANDLE: restored checklog_file name base: $options{checklog_file_ori}\n";
    print "PREHANDLE: restored checklog_file name base: $options{checkonhit_file_ori}\n";   
    chdir($Bin);    
    print "\nRUN: go back to working DIR $Bin\n";
}
sub cfgfparse{  
    my $cfgfname=shift;
    my $p_cfgfopt=shift;
    my $debugmode=shift;
        my ($normal,$debug,$extensive);
    if ($debugmode){
        $normal=$debugmode if ($debugmode=~/normal/ or $debugmode=~/1/);
        $debug=$debugmode if ($debugmode=~/debug/ or $debugmode=~/2/);
        $extensive=$debugmode if ($debugmode=~/extensive/ or $debugmode=~/3/);      
    }
    my ($globalsettings,$online,$logfile);      
    my ($logininfo,@login_cmds);
    my $data;                   
    my ($perlhandle,$simplereport);         
    my $cfgfh;
    open $cfgfh, "+<", $cfgfname or die $!;     
    print "\nCFGFPARSE: config file $cfgfname opened for read...\n" if ($debugmode);
    $|=1;
    print "\nCFGFPARSE: reading cfg file ...\n" if ($debugmode);
    print "\nCFGFPARSE: removing comments...\n" if ($debugmode);
    my $cfgfile=join '',<$cfgfh>;       
    $cfgfile=~s/((?:\s+)|^)#.*/$1/g;    
    $cfgfile=~s/^\s*\n//mg;         
    print "\nCFGFPARSE: the valid config read as following:\n[\n$cfgfile\n]\n" if $extensive;
    print "\nCFGFPARSE: configuration file parsing start:phase I...\n" if ($debugmode);
    print "\nCFGFPARSE: parsing step1 (->claused)...\n" if ($debugmode);
    my %clauses=($cfgfile=~/<(.*)>(.*?)<\/\1>/sig);
    foreach (keys %clauses){
        my $old=$_;
        s/(.*)/\L$1/;           
        $p_cfgfopt->{$_}{'clause'}=$clauses{$old};
    }
    print "\nCFGFPARSE: parsed step1 (=>claused) %cfgfopt looks:\n",Dumper($p_cfgfopt) if $extensive;
    print "\nCFGFPARSE: parsing step2 (=>hashed) ...\n" if ($debugmode);            
    foreach (keys %$p_cfgfopt){                     
        my $clausename=$_;
        my $clausevalue=$p_cfgfopt->{$clausename}{'clause'};        
        print "\nCFGFPARSE: current clause is:[$clausename]\n" if ($debug or $extensive);
        my %keyvalue=($clausevalue=~/^\s*?(\S+)\s*(.*?)\s*$/mig);   
        my @cliseq=($clausevalue=~/^\s*?\S+\s+\S+\s*=\s*{\s*(\S.*?\S)\s*}/mig);
        print "\nCFGFPARSE: cli sequences are:@cliseq\n" if ($debug or $extensive);
        my $clausevaluefromfile=readfrom2($keyvalue{'readfrom'});   
        if ($clausevaluefromfile){              
            print "\n   CFGFPARSE: returned value from data file is:\n$clausevaluefromfile\n" if ( $debug or $extensive);
            print "\n   CFGFPARSE: update the original clause...\n" if ( $debug or $extensive);
            $p_cfgfopt->{$clausename}{'clause'}=$clausevaluefromfile;   
            print "\n   CFGFPARSE: re-parsing the new clause...\n" if ( $debug or $extensive);
            %keyvalue=($clausevaluefromfile=~/^\s*?(\S+)\s*(.*?)\s*$/mig);  
        }else{
            print "\n   CFGFPARSE: nothing contained in data file!" if ( $debug or $extensive);
        }
        print "\n   CFGFPARSE: attach the parsed result into cfgfopt\n" if ($debug or $extensive);
        foreach (keys %keyvalue){                   
            my $oldkey=$_;
            s/(.*)/\L$1/;                       
            $p_cfgfopt->{$clausename}{'hash'}{$_}=$keyvalue{$oldkey};
        }
        $p_cfgfopt->{$clausename}{'commands'}=\@cliseq;
    }
    print "\nCFGFPARSE: parsed step2 (->hashed) %cfgfopt now looks:\n",Dumper($p_cfgfopt) if $extensive;
    print "\nCFGFPARSE: configuration file parsing done:phase I...\n" if ($debugmode);
}
sub cfgfparse2{     
    my $p_cfgfopt=shift;
    my $debugmode=shift;
        my $normal;
        my $debug;
        my $extensive;
    if ($debugmode){
        $normal=$debugmode if ($debugmode=~/normal/ or $debugmode=~/1/);
        $debug=$debugmode if ($debugmode=~/debug/ or $debugmode=~/2/);
        $extensive=$debugmode if ($debugmode=~/extensive/ or $debugmode=~/3/);      
    }
    if (0==keys %$p_cfgfopt){   
        print "\nCFGFPARSE2: no config file, skipping configuration file parsing stage II...\n";
        return ;
    }
    my ($logininfo_readfrom,$data_readfrom);
    my ($wanted,$cli,$ptn1,$ptn2);
    print "\nCFGFPARSE2: configuration file parsing start:phase II...\n" if ($debugmode);
    print "\nCFGFPARSE2: step3 parsing (logininfo hash->[login array])...\n" if ($debugmode);   
    foreach my $host (keys %{$p_cfgfopt->{logininfo}{hash}}){
        my @loginparams;            
        print "\n  CFGFPARSE2: get a host: $host\n"  if ($debug or $extensive);
        my $logininfo=$p_cfgfopt->{logininfo}{hash}{"$host"};
        if ($logininfo){
            push(@loginparams, ($logininfo=~/t1:(\d+.\d+.\d+.\d+)\s+/i));   
            push(@loginparams, ($logininfo=~/u1:(\S+)\s+/i));
            push(@loginparams, ($logininfo=~/p1:(\S+)\s*/i));
            push(@loginparams, ($logininfo=~/t2:(\d+.\d+.\d+.\d+)\s+/i));
            push(@loginparams, ($logininfo=~/u2:(\S+)\s+/i));
            push(@loginparams, ($logininfo=~/p2:(\S+)\s*/i));
            push(@loginparams, ($logininfo=~/e2:(\S+)\s*/i));
            print "\n  CFGFPARSE2: login info is:\n [ @loginparams ]\n" if ($debug or $extensive);
            $p_cfgfopt->{'logininfo'}{'hash'}{"$host"}=\@loginparams;
        }       
    }
    print "\nCFGFPARSE2: step4 parsing data clause...\n" if ($debugmode);   
    my $datatype;
    my (%cmdseq,$seq);
    foreach my $clausename (keys %$p_cfgfopt){  
        if ($clausename=~/data/){       
            print "\nCFGFPARSE2: step4 parsing ($clausename=>datatype,cli,wanted)...\n" if ($debugmode);    
            foreach (keys %{$p_cfgfopt->{"$clausename"}{'hash'}}) {
                $datatype=(/precheck/)?('precheck'):        
                    (/dotrue/)?('dotrue'):
                    (/dofalse/)?('dofalse'):
                    (/postcheck/)?('postcheck'):
                    (/^check\d+/)?('check'):
                    (/checkstate/)?('checkstate'):
                    (/checkchange/)?('checkchange'):
                    (/checkfinal/)?('checkfinal'):
                    ('');                   
                ($seq)=/(\d+)/ if /\d+/; 
                $seq=0 unless /\d+/;     
                print "\nCFGFPARSE2: seqnum in $_ is $seq\n" if ($debug or $extensive);
                if ($debug or $extensive){
                    print "\nCFGFPARSE2: datatype $datatype\n" if ($datatype);
                    print "\nCFGFPARSE2: unsupported datatype:$_\n" unless ($datatype);
                }
                next if (/checkstate/ or /checkchange/ or /checkfinal/); 
                next unless ($datatype);            
                my $dataline=$p_cfgfopt->{"$clausename"}{'hash'}{$_};       
                if ($dataline=~/\S/) {
                    print "\n  CFGFPARSE2: one $datatype line is:\n  [\n  $dataline\n  ]\n" if ($debug or $extensive);
                    ($wanted,$cli,$ptn1,$ptn2)=
                                ($dataline=~(/
                                        \s*
                                        (\w+)       
                                        \s*
                                        =       
                                        \s*{\s*
                                            (.*?)   
                                        \s*}\s*
                                        (?:
                                            (?:     
                                            :       
                                            \s*{\s*
                                                (.*?)   
                                            \s*}
                                            (?:     
                                                :
                                                \s*\{\s*
                                                    (.*?)   
                                                \s*\}\s*
                                            |           
                                            \s*         
                                            )
                                            )
                                            |       
                                            \s*     
                                        )
                                      /x)
                                );
                    print "  CFGFPARSE2: from cli:[$cli]\n   the wanted is:[$wanted]\n" if ($extensive and defined($ptn2));
                    $ptn1?print "\n    CFGFPARSE2: ptn1 is:$ptn1\n":print "\n    CFGFPARSE2: ptn1 undefined\n" if ($debug or $extensive);
                    $ptn2?print "\n    CFGFPARSE2: ptn2 is:$ptn2\n":print "\n    CFGFPARSE2: ptn2 undefined\n" if ($debug or $extensive);
                    $p_cfgfopt->{"$clausename"}{$datatype}{$cli}{$wanted}=[$ptn1,$ptn2];
                    $cmdseq{$datatype}{$seq}=$cli;
                }
            } 
            print "\nclause $clausename commands are tagged as following\n",Dumper(\%cmdseq) if ($extensive);
            foreach my $datatype (keys %cmdseq){            
                foreach my $seqnum (                
                            sort {$a <=> $b} (keys %{$cmdseq{$datatype}})
                            ){              
                    push @{$p_cfgfopt->{"$clausename"}{$datatype}{commands}},$cmdseq{$datatype}{$seqnum};
                }
                print "\nnow the $datatype are sorted as following\n          $datatype=> \n",Dumper($p_cfgfopt->{"$clausename"}{$datatype}{commands}) if($extensive);
            }
            print "\nCFGFPARSE2: step4 parsing ($clausename: checkstate/checkchange/checkfinal)...\n" if ($debugmode);  
            my $checkstate=$p_cfgfopt->{"$clausename"}{hash}{checkstate};   
            my $checkchange=$p_cfgfopt->{"$clausename"}{hash}{checkchange}; 
            my $checkfinal=$p_cfgfopt->{"$clausename"}{hash}{checkfinal};   
            if ($checkstate){               
                print "\$checkstate configured as: $checkstate\n" if ($verbose or $extensive);      
                $checkstate=~s/(\w+)/\@$1/g;        
                $checkstate=~s/ @(or|and) / $1 /g;  
                $checkstate=~s/\s*\@not /not /g;        
            }else{
                $checkstate='';
            }
            if ($checkchange){              
                print "\$checkchange configured as: $checkchange\n" if ($verbose or $extensive);
                $checkchange=~s/(\w+)/\$$1/g;
                $checkchange=~s/ \$(or|and) / $1 /g;
                $checkchange=~s/\s*\$not /not /g;
            }else{
                $checkchange='';
            }
            if($checkfinal){                
                print "\$checkfinal configured as: $checkfinal\n" if ($verbose or $extensive);
                $checkfinal=~s/(\w+)/\$$1_res/g;    
                $checkfinal=~s/ \$(or|and)_res / $1 /g; 
                $checkfinal=~s/\s*\$not_res /not /g;    
            }else{
                $checkfinal='';
            }
            $p_cfgfopt->{"$clausename"}{hash}{checkstate}=$checkstate;
            $p_cfgfopt->{"$clausename"}{hash}{checkchange}=$checkchange;
            $p_cfgfopt->{"$clausename"}{hash}{checkfinal}=$checkfinal;
        }   
    } 
    print "\nCFGFPARSE2: configuration file parsing done:phase II...\n" if ($debugmode);
    print "\nCFGFPARSE2: the final parsed %cfgfopt now looks:\n",
        Dumper(\%cfgfopt) if $extensive;
}
sub readfrom{           
    my $p_cfgfopt=shift;
    my $clausename=shift;
    my $clausevalue;
    my $readfrom=$p_cfgfopt->{$clausename}{'hash'}{'readfrom'};
    print "\nREADFROM: clause $clausename configured readfrom value: $readfrom\n" if defined $readfrom;
    return unless $readfrom;
    if ($readfrom=~/\s*(\w+\.?\w*)\s*/){                
        print "\nREADFROM: readfrom configured as file $1\n";
        $readfrom=$1;
        if (-f $readfrom){
            open my $datafh, "+<", $readfrom or die "READFROM: open file $readfrom for clause $clausename failed: $!\n";
            print "\nREADFROM: READFROM: file $readfrom opened for read...\n";
            $|=1;
            print "\nREADFROM: reading data file ...\n";
            $clausevalue=join '',<$datafh>;         
            $clausevalue=~s/#.*\n/\n/g;         
            $clausevalue=~s/^\s*\n//mg;         
            return $clausevalue;
        }else{
            print "\nREADFROM: file $readfrom does not exist!\n";
        }
    }elsif ($readfrom=~/^\s*\.\s*$/){               
        print "\nREADFROM: readfrom configured as current config file(.)\n";
    }else{
        print "\nREADFROM: illegal filename $readfrom!\n";
    }
}
sub readfrom2{          
    my $readfrom=shift;
    my $clausevalue;
    print "\n   READFROM2: configured readfrom value: $readfrom" if defined $readfrom;
    if (not defined $readfrom){
    }elsif ($readfrom=~/\s*(\S+\.?\w*)\s*/){            
        print "\n   READFROM2: the readfrom file configured as: $1";
        $readfrom=$1;
        if (-f $readfrom){  
            open my $datafh, "+<", $readfrom or die "READFROM2: open file $readfrom for the clause failed: $!\n";
            print "\n   READFROM2: file $readfrom opened for read...";
            $|=1;
            print "\n   READFROM2: reading data file ...\n";
            $clausevalue=join '',<$datafh>;         
            $clausevalue=~s/#.*\n/\n/g;         
            $clausevalue=~s/^\s*\n//mg;         
            return $clausevalue;
        }else{          
            print "\n   READFROM2: file $readfrom does not exist!\n";
            return undef;
        }
    }elsif ($readfrom=~/^\s*\.\s*$/){               
        print "\n   READFROM2: readfrom configured as current config file(.)\n";
    }else{
        print "\n   READFROM2: illegal filename $readfrom!\n";
    }
}
sub login{  
    my $p_loginparams=shift;        
    my $p_options=shift;
    my $debugmode=$p_options->{debug};
        my $normal=$debugmode if ($debugmode=~/normal/ or $debugmode=~/1/);
        my $debug=$debugmode if ($debugmode=~/debug/ or $debugmode=~/2/);
        my $extensive=$debugmode if ($debugmode=~/extensive/ or $debugmode=~/3/);       
    my $logfile=$p_options->{checklog_file};
    my $telnet_buffer=$p_options->{telnet_buffer};
    my $init_prompt=$p_options->{init_prompt};
    my $telnet_timeout=$p_options->{telnet_timeout};
    my $telnet1=    $p_loginparams->[0];    
    my $login1= $p_loginparams->[1];    
    my $password1=  $p_loginparams->[2];    
    my $telnet2=    $p_loginparams->[3];    
    my $login2= $p_loginparams->[4];    
    my $password2=  $p_loginparams->[5];    
    my $enable2=    $p_loginparams->[6];    
    my $t = new Net::Telnet (       
            Timeout => $telnet_timeout,
            Input_log => "$logfile",
            Prompt => $init_prompt,
            );
    print "\nLOGIN: create an initial input logs file (local timestamp only!): $logfile\n";
    $t->max_buffer_length($telnet_buffer);      
    if ($telnet1 and $login1 and $password1){       
        print "LOGIN: connecting to $telnet1\.\.\.\n";
        $t->open($telnet1);             
        $t->login($login1, $password1);         
        print "LOGIN: conneted to $telnet1 via user:$login1 and password:$password1\n" if ($debug or $extensive);
        if ($telnet2 and $login2 and $password2){   
            print "LOGIN: connecting to $telnet2\.\.\.\n";
            $t->cmd("telnet $telnet2");     
            $t->cmd("$login2");
            $t->cmd("$password2");  
            print "LOGIN: conneted to $telnet2 via user:$login2 and password:$password2\n"if ($debug or $extensive);
            if ($enable2){              
                print "LOGIN: enable 15 with enable password:$enable2\n";
                $t->cmd("enable");      
                $t->cmd("$enable2");
            }else{
                print "LOGIN: no enable password\n";    
            }
        }else{                      
            print "LOGIN: no 2nd login hop\n"
        }
    }
    else{
        print "LOGIN: wrong login info!\n";
    }
    print "\nLOGIN: the returned telnet instance is:",Dumper($t) if ($extensive);
    $t;                         
}
sub stsplit{            
    my $p_showtech=shift;
    my $p_cmdsoutput=shift;
    my $debugmode=shift;
    print "STSPLIT: show-tech file read:\n$$p_showtech\n" if $debugmode;
    my @cli_and_output=( $$p_showtech=~/\(tech-support\)\#\s    
                        (.*)            
                        \n([\d\D]+?)\n      
                        \[\d+\]\s       
                        (?=
                            (?:\(tech-support\)\#\s)  
                        )
                      /ixg );
    grep {$_=~s/^\s+|\s+$//g} @cli_and_output;
    %$p_cmdsoutput=@cli_and_output;
}
sub getobjfromcli2{
    my $paramnum=@_;
    my $clioutput=shift;
    my $ptn1=shift;
    my $ptn2=shift;
    my $debugmode=shift;
    my @value=();
    my $normal=$debugmode if ($debugmode=~/normal/ or $debugmode=~/1/);
    my $debug=$debugmode if ($debugmode=~/debug/ or $debugmode=~/2/);
    my $extensive=$debugmode if ($debugmode=~/extensive/ or $debugmode=~/3/);   
    if ($extensive){
        print "\nGETOBJFROMCLI: paramnum=$paramnum\n";
        print "\n                GETOBJFROMCLI: ptn1=[$ptn1]\n" if $ptn1;
        print "\n                GETOBJFROMCLI: ptn2=[$ptn2]\n" if $ptn2;
        print "\n                GETOBJFROMCLI: no patterns!\n" unless ($ptn1 or $ptn2);        
    }
    my $ptn1e=eval { qr/$ptn1/ } if ($ptn1);
    die "\nWrong regular expressions!=>$ptn1e\n$@\nCheck the way your capture data from commands!\n" if $@;
    my $ptn2e=eval { qr/$ptn2/ } if ($ptn2);
    die "\nWrong regular expressions!=>$ptn2e\n$@\nCheck the way your capture data from commands!\n" if $@;
    if ($ptn2){
        @value=$clioutput=~/$ptn1e([\d\D]*)$ptn2e/mg;
    }elsif($ptn1){
        @value=$clioutput=~/$ptn1e/smig;
    }else{
        @value=$clioutput=~/([\d\D]*)/mg;
    }
    return @value;
}
sub dataparse{
    my $p_options=shift;
    my $p_datatype=shift;
    my $p_cmdsoutputs=shift;
    my $p_data=shift;
    my $p_difftime=shift;
    my $t=$p_options->{telnet_obj};
    my $online=$p_options->{online};
    my $cli_prompt=$p_options->{cli_prompt};
    my $times=$p_options->{times};
    my $repeatmode=$p_options->{repeat};
    my $cmdslogfname=$p_options->{cmdlog_file};
    my $debugmode=$p_options->{debug};
        my $normal=$debugmode if ($debugmode=~/normal/ or $debugmode=~/1/);
        my $debug=$debugmode if ($debugmode=~/debug/ or $debugmode=~/2/);
        my $extensive=$debugmode if ($debugmode=~/extensive/ or $debugmode=~/3/);       
    print "\nDATAPARSE: parsing dataclause:...\n";
    my $ptn1;
    my $ptn2;
    my $cli;
    my @wanted;
    my $p_finalcmds;
    my $cmdslogfile;
    unless ($online){
        open FH, "< ../$cmdslogfname" 
            or die "DATAPARSE: open file $cmdslogfname fail: $!\n";
        print "\nCMDSLOGFILE2CMDSOUTPUTS: read cmdslogfile file $cmdslogfname ok...\n";
        $|=1;
        $cmdslogfile=join '',<FH>;  
    }
    my @cmds=@{$p_datatype->{commands}};    
=pod
    my @cliseq=@$p_cliseq;      
    my @seq=();
    foreach (0..$#cmds){
        my $index=$_;
        push @seq,( grep $cmds[$index] eq $cliseq[$_], (0..$#cliseq) );
    }
    my $min=min @seq;my $max=max @seq;
    @cmds=@cliseq[$min..$max];
=cut    
    my $temp4print=join("\n",@cmds);
    print "\nDATAPARSE: commands configured are:\n[\n$temp4print\n]\n" if $extensive;
    print "\nDATAPARSE: parsing commands one by one...\n" if $extensive;
    while ( @cmds and !$interupted ) {          
        my $cli_ori=$cli=shift @cmds;   
        my $p_cmds;
        print "\n    DATAPARSE: get one command:[$cli]\n" if $extensive;
        if ($cli=~/@(\S+)/){    
            print "\n        DATAPARSE: this looks an indirect command containing values to be replaced...\n" if $extensive;
            my $wanted=$1;              
            my $value=getvaluefromwanted($p_data,$wanted);  
            print "\n        DATAPARSE: the value of dparam [$wanted] is [@$value]\n" if $extensive;
            my @newclies;
            foreach (@$value){      
                $cli=~s/@(\S+)/$_/; 
                push @newclies,$cli;    
            }               
            print "\n        DATAPARSE: composing the real cli list [@newclies]\n" if $extensive;
            $p_cmds=\@newclies;     
        }else{                  
            print "\n        DATAPARSE: this looks a direct command...\n" if $extensive;
            $p_cmds=[$cli];         
        }
        if ($online){
            foreach (1..$times+1){      
                cmds2cmdsoutputs($t,$cli_prompt,$p_cmds,$p_cmdsoutputs,$p_options,$p_difftime);
            }
        }   
        else{
            cmdslogfile2cmdsoutputs($cmdslogfile,$p_cmds,$p_cmdsoutputs,$debugmode);        
        }
        print "\n        DATAPARSE: use cmd [$cli_ori] in cfgfopt tree to get wanted and ptns\n" if $extensive;
        @wanted=keys %{$p_datatype->{$cli_ori}};    
        print "\n            DATAPARSE: [cli]:[wanted] is: [$cli_ori] : [@wanted]\n" if $extensive;
        foreach (@wanted){          
            my $wanted=$_;
            ($ptn1,$ptn2)=@{$p_datatype->{$cli_ori}{$wanted}}[0,1]; 
            if ($extensive){
                print "\n                DATAPARSE: one [cli]:[wanted] is [$cli_ori]:[$_]\n";
                print "\n                DATAPARSE: using patten:[$ptn1][$ptn2]\n" if ($ptn1 and $ptn2);
                print "\n                DATAPARSE: using patten:[$ptn1][undef]\n" if ($ptn1 and not $ptn2);
                print "\n                DATAPARSE: no pattens\n" unless (defined $ptn1 or defined $ptn2)
            }
            foreach (@$p_cmds){
                my $realcli=$_;
                my @wantedvalue=();
                my $cmdoutput;
                $cmdoutput=$p_cmdsoutputs->{$realcli}{output} 
                    if (exists $p_cmdsoutputs->{$realcli}{output});
                if ($cmdoutput){
                    print "\nDATAPARSE: cli output exists..check the wanted values..\n" if ($debugmode);
                    @wantedvalue=getobjfromcli2($cmdoutput,$ptn1,$ptn2,$debugmode);
                    if ($debugmode){
                        @wantedvalue?(print "\nDATAPARSE: the wanted values are:\n@wantedvalue\n\n"):(print "\n                DATAPARSE: get no wanted values\n\n");
                    }
                }else{
                    print "\nDATAPARSE: cli output doesn't exist!\n" if ($debugmode);
                }
                $p_data->{$realcli}{$wanted}=\@wantedvalue;
            }
        }
    } 
    print "\n\nDATAPARSE: the cmdsoutputs structure looks:\n",Dumper($p_cmdsoutputs) if $extensive;
    print "\n\nDATAPARSE: the data structure looks:\n",Dumper($p_data) if $extensive;
}
sub cmds2cmdsoutputs{           
    my $t=shift;
    my $cli_prompt=shift;
    my $p_cmds=shift;
    my $p_cmdsoutputs=shift;
    my $p_options=shift;
    my $p_difftime=shift;
    my $rtimetype=$p_difftime->[0]; 
    my $dseconds=$p_difftime->[1];  
    my $timing=$p_options->{timing};
    my $repeatmode=$p_options->{repeat};
    my $debugmode=$p_options->{debug};
        my $normal=$debugmode if ($debugmode=~/normal/ or $debugmode=~/1/);
        my $debug=$debugmode if ($debugmode=~/debug/ or $debugmode=~/2/);
        my $extensive=$debugmode if ($debugmode=~/extensive/ or $debugmode=~/3/);       
    print "\n        CMDS2CMDSOUTPUTS: prepare to update cmds2cmdsoutputs from online...\n" if ($debug or $extensive);
    my $cmdoutput='';
    foreach (@$p_cmds){
        print "\n            CMDS2CMDSOUTPUTS: the command is:[$_]\n" if defined $extensive;    
        if( $$p_cmdsoutputs{$_} and (not $repeatmode)){ 
            print "\n            CMDS2CMDSOUTPUTS: the command output is already in hash,no need to update\n" if defined $extensive;
        }else{                      
            print "            CMDS2CMDSOUTPUTS: the command output is not present or repeatmode is set,get the output now...\n" if defined $extensive ;
            $cmdoutput=join '',$t->cmd(String => "$_",,Prompt=>$cli_prompt) ;
            print "\n            CMDS2CMDSOUTPUTS: the new output is:\n[\n",$cmdoutput,"\n]\n" if defined $extensive;
            print "            CMDS2CMDSOUTPUTS: put into cmdsoutputs DB...\n" if defined $extensive;
            $$p_cmdsoutputs{$_}{output}=$cmdoutput; 
            $$p_cmdsoutputs{$_}{localtime}=lr_time($timing,$p_difftime);
        }
    }
    print "\n        CMDS2CMDSOUTPUTS: cmds2cmdsoutputs checking&updating done...\n\n" if defined $extensive;
    return values %$p_cmdsoutputs;
}
sub cmdslogfile2cmdsoutputs{
    my $cmdslogfile=shift;
    my $p_cmds=shift;
    my $p_cmdsoutputs=shift;
    my $debugmode=shift;
        my $normal=$debugmode if ($debugmode=~/normal/ or $debugmode=~/1/);
        my $debug=$debugmode if ($debugmode=~/debug/ or $debugmode=~/2/);
        my $extensive=$debugmode if ($debugmode=~/extensive/ or $debugmode=~/3/);
    print "\n        CMDSLOGFILE2CMDSOUTPUTS: prepare to update cmds2cmdsoutputs from cmdslogfile...\n" if ($debug or $extensive);
    my $cli_prompt;
    foreach (@$p_cmds){
        my $cli_ori=my $cli=$_;
        if ($cli=~s/( )/\\$1/g){
            print "\n            CMDSLOGFILE2CMDSOUTPUTS: change cli for matching:[$cli]\n" if ($debug or $extensive);
        }
        if($cmdslogfile=~/\n            
                    (?:\[\d+\]\ )?  
                    (\S.*?)     
                    $cli        
                    [\f\t\r ]*  
                    \n      
                    \s*?        
                       (\S[\d\D]*?) 
                    \s*?        
                    (?:\[\d+\]\ )?  
                    (?:\1       
                    )
                 /x){           
            my $cli_prompt=$1;
            my $output=$2;
            print "\n            CMDSLOGFILE2CMDSOUTPUTS: detected prompt is now:...$cli_prompt...\n" if ($debug or $extensive);
            ($cli_prompt=~/\(tech-support\)\# /)?(print "\n            CMDSLOGFILE2CMDSOUTPUTS: this cmd looks come from a show-tech\n"):(print "\n            CMDSLOGFILE2CMDSOUTPUTS: this cmd looks come from a cmdslogfile\n" )  if ($debug or $extensive);
            print "\n            CMDSLOGFILE2CMDSOUTPUTS: detected outputs is now:\n[\n$output\n]\n" if ($debug or $extensive);
            $p_cmdsoutputs->{$cli_ori}{'output'}=$output;
            $p_cmdsoutputs->{$cli_ori}{'localtime'}=(localtime)." (make no sense under offlinemode)";
            print "\n            CMDSLOGFILE2CMDSOUTPUTS: updated cmdsoutputs\n" if ($debug or $extensive);
          }else{                    
              $p_cmdsoutputs->{$cli_ori}{'output'}=undef;
              $p_cmdsoutputs->{$cli_ori}{'localtime'}=(localtime)." (make no sense under offlinemode)";
              print "\n            CMDSLOGFILE2CMDSOUTPUTS: not found cmd [$cli] in cmdslogfile!\n";
              print "\n            CMDSLOGFILE2CMDSOUTPUTS: ignore this cmd in capture statement!\n";
          }  
    }
    print "\n        CMDSLOGFILE2CMDSOUTPUTS: cmds2cmdsoutputs checking&updating done...\n" if ($debug or $extensive);
}
sub getvaluefromwanted {
    my $p_data=shift;
    my $wanted=shift;
    my $cli;
    foreach (keys %$p_data){        
        $cli=$_;
        last if grep $_ eq $wanted,keys %{$p_data->{$cli}}; 
    }
    my $value = $p_data->{$cli}{$wanted};   
}
sub actionparse{            
    my $p_data=shift;
    my $datatype=shift;
    my $debugmode=shift;
        my $normal=$debugmode if ($debugmode=~/normal/ or $debugmode=~/1/);
        my $verbose=$debugmode if ($debugmode=~/verbose/ or $debugmode=~/2/);
        my $extensive=$debugmode if ($debugmode=~/extensive/ or $debugmode=~/3/);       
    print "\nACTIONPARSE: calculating actions...\n";
    my $dec_array='';
    my $dec_scalar='';
    my $dec_scalar_all='';
    my $print_test='';
    my $checkdata='';
    foreach my $cli (keys %$p_data){            
        foreach (keys %{$p_data->{"$cli"}}){        
            print "ACTIONPARSE: \n    got a \$wanted :[$_]\n" if $extensive;
            $dec_array .="    my \@$_=\@{\$$datatype"."{\'$cli\'}{\'$_\'}};\n";
            $dec_scalar .="    my \$$_=\$$_"."[0];\n";
            $dec_scalar_all .="    my \$$_"."_all=join '', \@$_;\n";
            $print_test.="    print \"    test:the wanted array [$_] looks:\@$_\\n\";\n" if $extensive;
            my @value=@{$p_data->{"$cli"}{"$_"}};
            $checkdata.=join '',@{$p_data->{"$cli"}{"$_"}};
            print "ACTIONPARSE: array value now is:@value\n" if ($verbose or $extensive);
        }
    }
    print "\nACTIONPARSE: action codes to be evaled for ($datatype) are as following:\n[\n\$dec_array:\n$dec_array\n\$dec_scalar:\n$dec_scalar\n\$dec_scalar_all:\n$dec_scalar_all\n\$print_test:\n$print_test\n]\n" if $extensive; 
    return  ($dec_array,$dec_scalar,$dec_scalar_all,$print_test,$checkdata);
;
}
sub datacompare{
    my $p_curdata=shift;
    my $p_olddata=shift;
    my $debug=shift;
    my $scalar_setflag;
    my $comp = Array::Compare->new;         
    foreach my $cli (keys %$p_curdata){         
        foreach (keys %{$p_curdata->{"$cli"}}){     
            my $p_curvalue=$p_curdata->{"$cli"}{"$_"};      
            my $p_oldvalue=$p_olddata->{"$cli"}{"$_"};      
            if ($comp->compare($p_curvalue, $p_oldvalue)) { 
                print "DATACOMPARE: value of ($_) are the same:\n@$p_oldvalue\n-------------\n@$p_curvalue\n" if ($debug>=2);
                $scalar_setflag.="my \$$_=0;\n";    
                print "DATACOMPARE: set $_ = 0\n=============\n" if ($debug>=2);
            }else{                  
                print "DATACOMPARE: value of ($_) are not same:\n@$p_oldvalue\n-------------\n@$p_curvalue\n" if ($debug>=2);
                $scalar_setflag.="my \$$_=1;\n";    
                print "DATACOMPARE: set $_ = 1\n=============\n" if ($debug>=2);
            }
        }
    }
    return $scalar_setflag;
}       
sub rulecalc{
    my $checkstate=shift;
    my $checkchange=shift;
    my $checkfinal=shift;
    my $dec_array=shift;
    my $dec_scalar=shift;
    my $scalar_setflag=shift;
    my $checkdata=shift;
    my $debug=shift;
    my $checkstate_res;
    my $checkchange_res;
    my $checkfinal_res;
    my $truefalse;
    if($checkchange){       
        my $checkchange_final=
                $scalar_setflag.
                "\$checkchange_res=".
                $checkchange.
                ";\n"
                ;
        print "\nRULECALC: \$checkchange_final to be evaled are:\n[\n$checkchange_final\n]\n" if ($debug>=2);
        print "RULECALC: now eval checkchange_final...\n";
        eval $checkchange_final;            
        print $@ if ($@);
        $truefalse=$checkchange_res;        
        print "\nRULECALC: \$checkchange_res after eval is: $checkchange_res\n\n" if ($debug>=2);
    }
    if($checkstate){        
        my $checkstate_final=
                $dec_array.
                "\$checkstate_res=".    
                $checkstate.
                ";\n"
                ;
        print "\nRULECALC: \$checkstate_final to be evaled are:\n[\n$checkstate_final\n]\n" if ($debug>=2);
        print "RULECALC: now eval checkstate_final...\n" if ($debug>=2);
        eval $checkstate_final;         
        print $@ if ($@);
        $truefalse=$checkstate_res;     
        print "\nRULECALC: \$checkstate_res after eval is: $checkstate_res\n\n" if ($debug>=2);
    }
    if($checkfinal){    
        my $checkfinal_final=
                "\$checkfinal_res=".    
                $checkfinal.
                ";\n"
                ;
        print "\nRULECALC: \$checkfinal_final to be evaled are:\n[\n$checkfinal_final\n]\n" if ($debug>=2);
        print "RULECALC: now eval checkfinal_final...\n";
        eval $checkfinal_final;         
        print $@ if ($@);
        $truefalse=$checkfinal_res;     
        print "\nRULECALC: \$checkfinal_res after eval is: $checkfinal_res\n\n" if ($debug>=2);
    }
    unless ($checkstate or $checkchange or $checkfinal){    
        $truefalse=($checkdata)?(1):(0);        
        print "\$truefalse by default is: $truefalse\n\n" if ($debug>=2);
    }
    return $truefalse;
}
sub cmdsoutputs_format{
    my $p_cmdsoutputs=shift;    
    my $p_res=shift;        
    my $i;
    my $cmds='';
    my $cmdsoutputs_ori='';
    my $cmdsoutputs='';
    foreach (keys %$p_cmdsoutputs){
        ++$i;
        $cmds.="$_\n";
        my $cli_fmt="$i)    $_  (at $p_cmdsoutputs->{$_}{localtime})";
        if ($p_cmdsoutputs->{$_}{output}){              
            $cmdsoutputs_ori.=$p_cmdsoutputs->{$_}{output};         
            $cmdsoutputs.=
                "$cli_fmt"                              
                ."\n"
                .'-' x (length $cli_fmt)                  
                ."\n"
                .$p_cmdsoutputs->{$_}{output}           
                ."\n\n\n"
                ;
        }else{                                          
            $cmdsoutputs.=
                "$cli_fmt"  
                ."\n"
                .'-' x (length $cli_fmt)
                ."\n"
                ."(no outputs)"                         
                ."\n\n\n"
                ;           
        }
    }
    @$p_res=($cmds,$cmdsoutputs,$cmdsoutputs_ori);
}
sub sendemail{      
    my $smtpserver=shift;
    my $from=shift;
    my $fake_from=shift;
    my $to=shift;
    my $replyto=shift;
    my $subj=shift;
    my $msgs=shift;
    my $p_files=shift;
    print "\nSENDEMAIL: now send an email...\n";
    eval {
        my $sender=new Mail::Sender{                
            smtp =>     $smtpserver,
            from =>     $from,
            to =>       $to,
            fake_from =>    $fake_from,
            replyto =>  $replyto,
        };
        (
          ref ($sender->MailFile(
              {subject =>   $subj,
               msg =>   $msgs,
               file =>  $p_files,
              })
              )
          and print "\nSENDEMAIL: email sent successfully.\n"
         )
         or die "$Mail::Sender::Error\n";       
    };
    print "can't send email!\n[\n$@\n]\n" if ($@);
}
sub addtime{
    my $string=shift;       
    my $force=shift;        
    my $timing=shift;       
    my $p_difftime=shift;       
    my $time;
    $time=(defined $timing)?lr_time($timing,$p_difftime):localtime;
    $time=~s/^|\s+|:/_/g;       
    if ($force){            
        ($string=~/%t/)?($string=~s/%t/$time/): 
        $string=~s/(.*)\.\w+$/$1$time/;     
    }else{              
        $string=~s/%t/$time/;   
    }
    return $string;
}
sub addhost{
    my $string=shift;
    my $host=shift;
    $string=~s/%h/_$host/;
    return $string;
}
sub cli_prompt{
    my $t=shift;
    my $cli=shift;
    my $debug=shift;
    my $cli_prompt;
    print "\nPROMPT: detecting a proper prompt for later commands...\n";    
    my @pwd=$t->cmd("\n");
    print "PROMPT: the current working dir:\n[\n@pwd\n]\n" if ($debug);
    my $prompt_ori=$cli_prompt=$pwd[1];  
    $cli_prompt=~s#\@#\\\@#;
    $cli_prompt=~s#\[#\\\[#;        
    $cli_prompt=~s#\]#\\\]#;        
    $cli_prompt=~s#^#/#;        
    $cli_prompt=~s#$#/#;        
    print "\nPROMPT: A prompt{$prompt_ori}detected\n" if ($debug);
    return $cli_prompt;
}
sub time_diff{
    my $localtime=shift;
    my $remotetime=shift;
    my $lseconds=parsedate("$localtime");
    my $rseconds=parsedate("$remotetime");
    my $timetype=($remotetime=~/gmt/i)?'gm':'local';
    my $diffseconds=$rseconds-$lseconds;    
    my $dseconds=$diffseconds;
    $dseconds=abs $dseconds;
    my $seconds = $dseconds % 60;
    $dseconds = ($dseconds - $seconds) / 60;
    my $minutes = $dseconds % 60;
    $dseconds = ($dseconds - $minutes) / 60;
    my $hours = $dseconds % 24;
    $dseconds = ($dseconds - $hours) / 24;
    my $days = $dseconds % 7;
    my $weeks = ($dseconds - $days) / 7;
    return ($timetype,$diffseconds,$weeks,$days,$hours,$minutes,$seconds);  
}
sub zipbigfile{
    my $p_options=shift;            
    my $p_difftime=shift;           
    my $size2zip=$p_options->{size2zip};    
    my $timing=$p_options->{timing};
    my $host=$p_options->{host};
    my $checklog_file=$p_options->{checklog_file};
    my $checkonhit_file=$p_options->{checkonhit_file};  
    $p_options->{$checklog_file}        =   $p_options->{checklog_file_ori};
    $p_options->{$checkonhit_file}  =   $p_options->{checkonhit_file_ori};
    foreach my $file2zip (  $checklog_file, $checkonhit_file ) {        
        print "ZIPBIGFILE: \nfile to be checked is $file2zip\n";
        my $filesize=-s $file2zip;              
        if ($filesize > $size2zip){             
            print "\nZIPBIGFILE: size of log file $file2zip ($filesize) exceeds the max. limitation($size2zip), need to be zipped...\n";        
            print "\nZIPBIGFILE: file base is $p_options->{$file2zip}\n";
            my $file2zip_new=parsename( $p_options->{$file2zip},
                                                                    $host,
                                                                    1,
                                                                    $timing,
                                                                    $p_difftime);
            print "\nZIPBIGFILE: prepared a new file name $file2zip_new...\n";
            copy($file2zip,$file2zip_new);          
            print "\nZIPBIGFILE: copied logs from $file2zip to $file2zip_new...\n";
            my $zip=Archive::Zip->new();                
            my $file_member=$zip->addFile( "$file2zip_new");    
            my $file2zip_new_zip=$file2zip_new;
            $file2zip_new_zip=~s/(.txt)$/.zip/;         
            unless ( $zip->writeToFileNamed("$file2zip_new_zip")==AZ_OK ){ 
                 die 'write error when zipping';            
            }
            print "\nZIPBIGFILE: saved as a new zip file: $file2zip_new_zip\n";     
            unlink "$file2zip_new";                 
            `echo > $file2zip`;                 
            $filesize=-s $file2zip;                 
            print "\nZIPBIGFILE: empty original log file $file2zip(now size is $filesize)...\n";
        }else{
            print "\nZIPBIGFILE: size of log file $file2zip ($filesize) is still within the max. limitation($size2zip), no need to be zipped for now...\n"; 
        }
    }
}
sub get_commands{
    return {
        "usage" => {
            desc => "usage",
            maxargs => 0, 
            proc => sub { print USAGEMSG2},
        },
        "cd" => {
            desc => "Change to directory DIR",
            maxargs => 1, 
            args => sub { shift->complete_onlydirs(@_); },
            proc => sub { chdir($_[0] || $ENV{HOME} || $ENV{LOGDIR}); },
        },
        "help" => {
            desc => "Print helpful information",
            args => sub { shift->help_args(undef, @_); },
            method => sub { shift->help_call(undef, @_); }
        },
        "h" => { alias => "help", exclude_from_completion=>1},
        "?" =>  { syn => "help" },
        "quit" => {
            desc => "Quit this program", maxargs => 0,
            method => sub { shift->exit_requested(1); },
        },
        "exit" =>  { syn => "quit" },        
        "bye" =>  { syn => "quit" },        
        "logout" =>  { syn => "quit" },
        "delete" => { desc => "Delete FILEs",
            args => sub { shift->complete_onlyfiles(@_); },
            minargs => 1,
            proc => sub { danger() && (unlink(@_) or warn "Could not delete: $!\n") } 
        }, 
        "pwd" => {
            desc => "Print the current working directory",
            maxargs => 0, proc => sub { print "$Bin\n"},
        },
        "ls" =>  { syn => "list" },
        "dir" => { syn => "ls" },
        "list" => { desc => "List files in DIRs",
            args => sub { shift->complete_onlydirs(@_); },
            proc => sub { system('ls', '-FClg', @_); } 
        }, 
        "rename" => { desc => "Rename FILE to NEWNAME",
            args => sub { shift->complete_files(@_); },
            minargs => 2, maxargs => 2,
            proc => sub { danger() && system('mv', @_); } 
        },
        "stat" =>   { desc => "Print out statistics on FILEs",
                      args => sub { shift->complete_files(@_); },
                      proc => \&print_stats },
        "view" =>   { desc => "View the contents of FILEs",
                      args => sub { shift->complete_onlyfiles(@_); },
                      proc => sub { system('cat', @_); } 
        },
        "cat" =>    { syn => "view" },
        debug_complete => { desc => "Turn on completion debugging",
            minargs => 1, maxargs => 1, 
            args => "0=off 1=some, 2=more, 3=tons",
            proc => sub { $term->{debug_complete} = $_[0] },
        },      
        "show" => {
            desc => "checking settings",
            cmds => {
                "warranty" => { proc => "You have no warranty!\n" },
                "args" => {
                    minargs => 2, maxargs => 2,
                    args => [ 
                            sub {qw(create delete)},
                            \&Term::ShellUI::complete_files 
                        ],
                    desc => "Demonstrate method calling",
                    method => sub {
                        my $self = shift;
                        my $parms = shift;
                        print $self->get_cname($parms->{cname}).": ".join(" ",@_), "\n";
                    },
                },
                "current" => { 
                    proc => sub {
                            my $option=shift;
                            if($option){
                                print "$option is: $options{$option}\n";
                            }else{
                                my $dd=Data::Dumper->new([\%options], [qw(*current)]);                          
                                print "Current settings are:\n",$dd->Dump;
                            }
                    },
                },
                "default" => { 
                    proc => sub {
                            my $option=shift;
                            if($option){
                                ( $options_def{$option} ) ? 
                                	(print "$option defaults to: $options_def{$option}\n")
                                	: (print "no default value for this option!\n");
                            }else{
                                my $dd=Data::Dumper->new([\%options_def], [qw(*default)]);                          
                                print "default settings are:\n",$dd->Dump;                              
                            }
                        }
                },
            },
        },
        "reset_all" => {
            desc => "Resetting all parameters to defaults",
            maxargs => 0, 
            proc => sub { 
							%options=%options_def; 
							print "all parameters are set to their defaults.\n";
							print "use \'show default\' to check current defaults.\n";
							},         
        },
        "run" => {
            desc => "run the checking", maxargs => 0,
            proc => \&run,
        },
        "online" => {
            desc => "online mode:[0|1]", minargs => 0, maxargs => 1,
            proc => sub { (@_) 				? (print "value is set to:",$options{online}=shift,"\n"):
            			  (defined $options{online})? (print "current value is :$options{online}\n"):
            			  					  (print "current value is none!\n");
            			  },
        },
        "repeat" => {
            desc => "repeat mode:[0|1]", minargs => 0, maxargs => 1,
            proc => sub { (@_) 				? (print "value is set to:",$options{repeat}=shift,"\n"):
            			  (defined $options{repeat})? (print "current value is :$options{repeat}\n"):
            			  					  (print "current value is none!\n");
            			  },
        },
        "times" => {
            desc => "times of a cmd to repeat before execute the next one:[0..N]", 
            minargs => 0, maxargs => 1,
            proc => sub { (@_) 				? (print "value is set to:",$options{times}=shift,"\n"):
            			  (defined $options{times})? (print "current value is :$options{times}\n"):
            			  					  (print "current value is none!\n");
            			  },
        },
        "rounds" => {
            desc => "rounds of checks:[1..N]", 
            minargs => 0, maxargs => 1,
            proc => sub { (@_) 				? (print "value is set to:",$options{rounds}=shift,"\n"):
            			  (defined $options{rounds})? (print "current value is :$options{rounds}\n"):
            			  					  (print "current value is none!\n");
            			  },
        },
        "sleep" => {
            desc => "sleep interval between each round:[0..N]", 
            minargs => 0, maxargs => 1,
            proc => sub { (@_) 				? (print "value is set to:",$options{sleep}=shift,"\n"):
            			  (defined $options{sleep})	? (print "current value is :$options{sleep}\n"):
            			  					  (print "current value is none!\n");
            			  },
        },
        "debug" => {
            desc => "debug mode:[0|1|2|3]", 
            minargs => 0, maxargs => 1,
            proc => sub { (@_) 				? (print "value is set to:",$options{debug}=shift,"\n"):
            			  (defined $options{debug})? (print "current value is :$options{debug}\n"):
            			  					  (print "current value is none!\n");
            			  },
        },
        "cli_prompt" => {
            desc => "cli_prompt used by telnet to chunk the cmdoutput", 
            minargs => 0, maxargs => 1,
            proc => sub { (@_) 			? (print "value is set to:",$options{cli_promt}=shift,"\n"):
            			  (defined $options{cli_prompt})? (print "current value is :$options{cli_prompt}\n"):
            			  					  (print "current value is none!\n");
            			  },
        },
        "init_prompt" => {
            desc => "prompt used by telnet to input username/password",
            minargs => 0, maxargs => 1,
            proc => sub { (@_) 			? (print "value is set to:",$options{init_prompt}=shift,"\n"):
            			  (defined $options{init_prompt})? (print "current value is :$options{init_prompt}\n"):
            			  					  (print "current value is none!\n");
            			  },
        },
        "timing" => {
            desc => "time used in the log:[local|remote]", 
            minargs => 0, maxargs => 1,
            proc => sub { (@_) 				? (print "value is set to:",$options{timing}=shift,"\n"):
            			  (defined $options{timing})? (print "current value is :$options{timing}\n"):
            			  					  (print "current value is none!\n");
            			  },
        },
        "clock_cmd" => {
            desc => "cmd used to get the current clock on the remote device under check (usually [show clock|date])",
            minargs => 0, maxargs => 1,
            proc => sub { (@_) 			? (print "value is set to:",$options{clock_cmd}=shift,"\n"):
            			  (defined $options{clock_cmd})? (print "current value is :$options{clock_cmd}\n"):
            			  					  (print "current value is none!\n");
            			  },
        },
        "telnet_buffer" => {
            desc => "telnet buffer in Megabits:[1..N]",
            minargs => 0, maxargs => 1,
            proc => sub { (@_) 		? (print "value is set to:",$options{telnet_buffer}=shift,"\n"):
            			  (defined $options{telnet_buffer})? (print "current value is :$options{telnet_buffer}\n"):
            			  					  (print "current value is none!\n");
            			  },
        },          
        "telnet_timeout" => {
            desc => "telnet timeout in second:[1..N]",
            minargs => 0, maxargs => 1,
            proc => sub { (@_) 		? (print "value is set to:",$options{telnet_timeout}=shift,"\n"):
            			  (defined $options{telnet_timeout})? (print "current value is :$options{telnet_timeout}\n"):
            			  					  (print "current value is none!\n");
            			  },
        },
        "ziplog" => {
            desc => "zip the log", 
            minargs => 0, maxargs => 1,
            proc => sub { (@_) 				? (print "value is set to:",$options{ziplog}=shift,"\n"):
            			  (defined $options{ziplog})? (print "current value is :$options{ziplog}\n"):
            			  					  (print "current value is none!\n");
            			  },
        },
        "size2zip" => {
            desc => "file size max limit before get zipped", 
            minargs => 0, maxargs => 1,
            proc => sub { (@_) 				? (print "value is set to:",$options{size2zip}=shift,"\n"):
            			  (defined $options{size2zip})? (print "current value is :$options{size2zip}\n"):
            			  					  (print "current value is none!\n");
            			  },
        },
        "dotrue" => {
            desc => "forcing the dotrue statement:[0|1]", 
            minargs => 0, maxargs => 1,
            proc => sub { (@_) 				? (print "value is set to:",$options{dotrue}=shift,"\n"):
            			  (defined $options{dotrue})? (print "current value is :$options{dotrue}\n"):
            			  					  (print "current value is none!\n");
            			  },
        },
        "dofalse" => {
            desc => "forcing the dofalse statement:[0|1]", 
            minargs => 0, maxargs => 1,
            proc => sub { (@_) 				? (print "value is set to:",$options{dofalse}=shift,"\n"):
            			  (defined $options{dofalse})? (print "current value is :$options{dofalse}\n"):
            			  					  (print "current value is none!\n");
            			  },
        },
        "host" => {
            desc => "name of host to be checked", 
            minargs => 0, maxargs => 1,
            proc => sub { (@_) 				? (print "value is set to:",$options{host}=shift,"\n"):
            			  (defined $options{host})	? (print "current value is :$options{host}\n"):
            			  					  (print "current value is none!\n");
            			  },
        },
        "config_file" => {
            desc => "configuration file name", 
            minargs => 0, maxargs => 1,
            args => sub { shift->complete_files(@_); },
            proc => sub { (@_) 				? (print "value is set to:",$options{config_file}=shift,"\n"):
            			  (defined $options{config_file})? (print "current value is :$options{config_file}\n"):
            			  					  (print "current value is none!\n");
            			  },
        },
        "log_dir" => {
            desc => "dir for all checking logs", 
            minargs => 0, maxargs => 1,
            args => sub { shift->complete_files(@_); },
            proc => sub { (@_) 				? (print "value is set to:",$options{log_dir}=shift,"\n"):
            			  (defined $options{log_dir})? (print "current value is :$options{log_dir}\n"):
            			  					  (print "current value is none!\n");
            			  },
        },
        "checklog_file" => {
            desc => "all checking logs", 
            minargs => 0, maxargs => 1,
            args => sub { shift->complete_files(@_); },
            proc => sub { (@_) 				? (print "value is set to:",$options{checklog_file}=shift,"\n"):
            			  (defined $options{checklog_file})? (print "current value is :$options{checklog_file}\n"):
            			  					  (print "current value is none!\n");
            			  },
        },
        "checkonhit_file" => {
            desc => "checking logs when hitting the issue", 
            minargs => 0, maxargs => 1,
            args => sub { shift->complete_files(@_); },
            proc => sub { (@_) 				? (print "value is set to:",$options{checkonhit_file}=shift,"\n"):
            			  (defined $options{checkonhit_file})? (print "current value is :$options{checkonhit_file}\n"):
            			  					  (print "current value is none!\n");
            			  },
        },
        "cmdlog_file" => {
            desc => "name of log file to be checked", 
            minargs => 0, maxargs => 1,
            args => sub { shift->complete_files(@_); },
            proc => sub { (@_) 				? (print "value is set to:",$options{cmdlog_file}=shift,"\n"):
            			  (defined $options{cmdlog_file})? (print "current value is :$options{cmdlog_file}\n"):
            			  					  (print "current value is none!\n");
            			  },
        },
        "sendemail" => {
            desc => "send email once detecting any issues:[0|1]", 
            minargs => 0, maxargs => 1,
            proc => sub { (@_) 				? (print "value is set to:",$options{sendemail}=shift,"\n"):
            			  (defined $options{sendemail})? (print "current value is :$options{sendemail}\n"):
            			  					  (print "current value is none!\n");
            			  },
        },
        "smtpserver" => {
            desc => 'smtpserver:[e.g.: smtp.redback.com]', 
            minargs => 0, maxargs => 1,
            proc => sub { (@_) 				? (print "value is set to:",$options{smtpserver}=shift,"\n"):
            			  (defined $options{smtpserver})? (print "current value is :$options{smtpserver}\n"):
            			  					  (print "current value is none!\n");
            			  },
        },
        "emailfrom" => {
            desc => 'emailfrom:[e.g.:pingsong@redback.com ]', 
            minargs => 0, maxargs => 1,
            proc => sub { (@_) 				? (print "value is set to:",$options{emailfrom}=shift,"\n"):
            			  (defined $options{emailfrom})? (print "current value is :$options{emailfrom}\n"):
            			  					  (print "current value is none!\n");
            			  },
        },
        "emailfakefrom" => {
            desc => 'fake emailfrom:[e.g.:routermonitor@ericsson.com]', 
            minargs => 0, maxargs => 1,
            proc => sub { (@_) 				? (print "value is set to:",$options{emailfakefrom}=shift,"\n"):
            			  (defined $options{emailfakefrom})? (print "current value is :$options{emailfakefrom}\n"):
            			  					  (print "current value is none!\n");
            			  },
        },
        "emailto" => {
            desc => 'send email to:[e.g.:wang@cmcc.com]', 
            minargs => 0, maxargs => 1,
            proc => sub { (@_) 				? (print "value is set to:",$options{emailto}=shift,"\n"):
            			  (defined $options{emailto})? (print "current value is :$options{emailto}\n"):
            			  					  (print "current value is none!\n");
            			  },
        },
        "emailreplyto" => {
            desc => 'email reply to:[e.g.:pingsong@ericsson.com]', 
            minargs => 0, maxargs => 1,
            proc => sub { (@_) 				? (print "value is set to:",$options{emailreplyto}=shift,"\n"):
            			  (defined $options{emailreplyto})? (print "current value is :$options{emailreplyto}\n"):
            			  					  (print "current value is none!\n");
            			  },
        },
        "emailsubj" => {
            desc => "email subject:[emergency issue:link is down!]", 
            minargs => 0, maxargs => 1,
            proc => sub { (@_) 				? (print "value is set to:",$options{emailsubj}=shift,"\n"):
            			  (defined $options{emailsubj})? (print "current value is :$options{emailsubj}\n"):
            			  					  (print "current value is none!\n");
            			  },
        },
        "emailpref" => {
            desc => "some headword in the email:[there is a link down issue,for more info please see attachment...]", 
            minargs => 0, maxargs => 1,
            proc => sub { (@_) 				? (print "value is set to:",$options{emailpref}=shift,"\n"):
            			  (defined $options{emailpref})? (print "current value is :$options{emailpref}\n"):
            			  					  (print "current value is none!\n");
            			  },
        },
        "emailmax" => {
            desc => "max. size of email text:[0..N]", 
            minargs => 0, maxargs => 1,
            proc => sub { (@_) 				? (print "value is set to:",$options{emailmax}=shift,"\n"):
            			  (defined $options{emailmax})? (print "current value is :$options{emailmax}\n"):
            			  					  (print "current value is none!\n");
            			  },
        },
    };
}
sub checkoptions4cli{
    my $options=shift;
    my $options_cli=shift;
    my $options_def=shift;
    my $cfgfopt=shift;
    %$options=%$options_def;                            
    my $getopt = GetOptions (       
            "shell"     =>  \$options_cli->{shell},     
            "history_shell" => \$options_cli->{history_shell},
            "usage"     =>  \$options_cli->{usage},     
            "online!"   =>  \$options_cli->{online},    
            "offline"   =>  sub {                       
                            $options_cli->{online}=0;
                            $options_cli->{rounds}=1;
                            $options_cli->{sleep}=0;
                        },                              
            "repeat!"   =>  \$options_cli->{repeat},    
            "times=i"   =>  \$options_cli->{times},     
            "rounds=i"  =>  \$options_cli->{rounds},    
            "sleep=i"   =>  \$options_cli->{sleep},     
            "nosleep"   =>  sub {$options_cli->{sleep}=0},
            "debug=i"   =>  \$options_cli->{debug},     
            "nodebug|quiet" =>  sub {$options_cli->{debug}=0},  
            "nochecklog"    =>  sub {$options_cli->{checklog_file}=''},
            "cli_prompt"    =>  \$options_cli->{cli_prompt},
            "timing=i"  =>  \$options_cli->{timing},
            "clock_cmd=i"   =>  \$options_cli->{clock_cmd},
            "telnet_timeout=i" =>   \$options_cli->{telnet_timeout},
            "telnet_buffer=i" =>    \$options_cli->{telnet_buffer},
            "init_prompt=s" =>  \$options_cli->{init_prompt},
            "ziplog!"   =>  \$options_cli->{ziplog},
            "size2zip=i" => \$options_cli->{size2zip},
            "dotrue!"   =>  sub {$options_cli->{truefalse}=1},
            "dofalse!"  =>  sub {$options_cli->{truefalse}=0},
            "host|hostname=s" =>    \$options_cli->{host},
            "config_file|cfg=s" =>  \$options_cli->{config_file},   
            "log_dir|logdir=s"  =>  \$options_cli->{log_dir},    
            "checklog_file|checklog=s" =>   \$options_cli->{checklog_file},
            "checkonhit_file|hit=s" =>  \$options_cli->{checkonhit_file},
            "cmdlog_file|cmdlog=s" =>   \$options_cli->{cmdlog_file},
            "sendemail!"    =>  \$options_cli->{sendemail}, 
            "smtpserver=s"  =>  \$options_cli->{smtpserver},
            "emailfrom=s"   =>  \$options_cli->{emailfrom},
            "emailfakefrom=s" =>    \$options_cli->{emailfakefrom},
            "emailto=s" =>  \$options_cli->{emailto},
            "emailreplyto=s" => \$options_cli->{emailreplyto},
            "emailsubj=s"   =>  \$options_cli->{emailsubj},
            "emailpref=s"   =>  \$options_cli->{emailpref}, 
            "emailmax=i"    =>  \$options_cli->{emailmax},
            "help|?"    =>  \$options_cli->{help},      
            );
    grep {$options_cli->{$_}=~s/(.*)/\L$1/ if (defined $options_cli->{$_})} (keys %$options_cli); 
    if (!$getopt or                                     
        $options_cli->{help}                            
        ){
        print "\nhelp information!\n";                  
        die USAGEMSG;
    };
    if ($options_cli->{usage}){                         
        die USAGEMSG2;                                  
    }
    $options->{debug}=$options_cli->{debug}             
        if (defined $options_cli->{debug});             
    print "CHECKOPTIONS4CLI: options from defaults are:\n",Dumper($options) if ($options->{debug}==3);
    eval {$options->{$_}=$ENV{$_} 
        if (defined $ENV{$_})} foreach (keys %options);
    eval {$options->{$_}=$ENV{$_} 
        if (defined $ENV{$_})} foreach (keys %options_cli);
    if(
        (   not (defined $options_cli->{shell})         
            and                                         
        (
            (                                           
            not (defined $options_cli->{host})
            )
            or                                          
            (                                           
                ($options_cli->{online})                
                and
                not (defined $options_cli->{host})  
            )   
        )
        )
      ){                                                
        print "\nCHECKOPTIONS4CLI: wrong parameter combinations!\n";
        print "\nCHECKOPTIONS4CLI:  1) host is a MUST unless under shell mode!\n";
        die USAGEMSG2;      
    }
    $options->{debug}=$options_cli->{debug}             
        if (defined $options_cli->{debug});             
    print "CHECKOPTIONS4CLI:: options after env. are:\n",           
        Dumper($options) if ($options->{debug}==3);
    print "\nCHECKOPTIONS4CLI:########analyzing configuration file#############\n\n" 
        if ($options->{debug});
    $options->{config_file} = $options_cli->{config_file} 
        if ( defined $options_cli->{config_file} ); 
    cfgfparse(  $options->{config_file}, 
                $cfgfopt,$options->{debug} 
                );                                      
    foreach (keys %options){                            
        eval {
            if (exists $cfgfopt->{globalsettings}){     
                if (exists $cfgfopt->{globalsettings}{hash}){   
                    $options->{$_}=$cfgfopt->{globalsettings}{hash}{$_} 
                        if (defined $cfgfopt->{globalsettings}{hash}{$_});
                }
            }
        }
    }
    if (exists $cfgfopt->{globalsettings}){             
        if (exists $cfgfopt->{globalsettings}{hash}){   
            eval {  $options->{$_}  =   $cfgfopt->{globalsettings}{hash}{$_} 
                    if (    $cfgfopt->{globalsettings}{hash}{$_}    )
                 }
                foreach (keys %{$cfgfopt->{globalsettings}{hash}});
        }
    }   
    $options->{debug}=$options_cli->{debug}             
        if (defined $options_cli->{debug});             
    print "CHECKOPTIONS4CLI:: options after config file are:\n",
        Dumper($options) if ($options->{debug}==3);
    eval {  $options->{$_}=$options_cli->{$_} 
            if (defined $options_cli->{$_})
        } 
        foreach keys %options;
    eval {$options->{$_}=$options_cli->{$_} 
            if (defined $options_cli->{$_})
         } 
        foreach keys %options_cli;
    print "CHECKOPTIONS4CLI:: options after CLI are:\n", 
        Dumper($options) if ($options->{debug}==3);
    die USAGEMSG2 if (                                  
                not $options->{shell}                   
                and                                     
                (                                       
                $options->{online} 
                and 
                not (defined $options->{host})  
                )   
            );
}       
sub interuption_handler{
    if ($interupted==0){
        $interupted=1 ; 
        print "\nINTERUPTION_HANDLER: user stopped the checking loop, will exit soon...\n";
    }else{
        print "\nINTERUPTION_HANDLER: Sorry,Ctrl+C will not quit, use 'quit|exit|bye' to exit\n";
    }
}
sub clear_interuption{
    $interupted=0;
}
sub print_stats
{
    for my $file (@_) {
        stat($file) or die "No $file: $!\n";    
        print "$file has $st_nlink link" . ($st_nlink==1?"":"s") .
            ", and is $st_size byte" . ($st_size==1?"":"s") . " in length.\n";
        print "Inode Last change at: " . localtime($st_ctime) . "\n";
        print "      Last access at: " . localtime($st_atime) . "\n";
        print "    Last modified at: " . localtime($st_mtime) . "\n";
    }
}
sub danger
{
    print "performing a dangerous task!\n";
    return 1;
}
sub audit{
    print "\n\n#######################action parse###############################\n\n";
    ($dec_array,$dec_scalar,$dec_scalar_all,$print_test)=
        (actionparse(\%precheckdata,"precheckdata",$options{debug}))[0,1,2,3];
    my $declare = $dec_array.$dec_scalar.$dec_scalar_all;
    print "\nAUDIT: the \$declare now looks:\n[\n$declare\n]\n" if $extensive;      
    my $normalcapture_delim="\n    print \"==============normal capture codes==============\\n\";\n";
    my $print_test_delim="\n    print \"=================test captures================\\n\";\n";
    my $perlhandleclause_delim="\n    print \"\\n\\n==============perlhandle clause:===============\\n\";\n";
    my $perlhandleclause=$cfgfopt{perlhandle}{clause};
    $perlhandleclause='' unless $perlhandleclause;
    my $simplereportclause_delim="    print \"\\n\\n==============simplereport clause:==============\\n\";\n";
    my $reportprefix="\nprint <<\"HERE\"\n\n\n\n";
    my $simplereportclause=$cfgfopt{simplereport}{clause};
    $simplereportclause='' unless defined $simplereportclause;
    my $reportsuffix="\nHERE\n";
    my $action=$normalcapture_delim.
        $declare."\n\n\n".
        $print_test_delim.
        $print_test.
        $perlhandleclause_delim.
        $perlhandleclause.
        $simplereportclause_delim.
        $reportprefix.
        $simplereportclause.
        $reportsuffix;
    print "\nAUDIT: actions to be evaled are:\n[\n$action\n]\n" if ($verbose or $extensive);
    print "\nAUDIT:#######################action execution###########################\n\n";
    eval $action if $action=~/\w+/;         
    if ($@){                    
        print "\nAUDIT: Error:\n[\n$@\n]\n";
        print "\nAUDIT: there are syntax error in your config action definition!\n";
        print "\nAUDIT: most probably the perlhandle clause contains progma/syntax, or the var name used in action clause is different than those defined in data clause!\n";
    }
}   
sub time_diff_print{
    my $p_difftime=shift;
    my $debug=shift;
    my $dseconds=$p_difftime->[1];
    my $abs=abs $dseconds;
    if ($debug){
        ($dseconds==0)?
            (print "\nTIME_DIFF_PRINT: time is synchronized perfect with remote!\n"):
        ($dseconds<0)?
            (print "\nTIME_DIFF_PRINT: remote is running earlier than local by ${abs}s\n"):
            (print "\nTIME_DIFF_PRINT: remote is running later than local by ${abs}s\n");
        print "\nTIME_DIFF_PRINT: which is $p_difftime->[2]weeks, $p_difftime->[3]days, $p_difftime->[4]h:$p_difftime->[5]m:$p_difftime->[6]s\n" unless ($dseconds==0);
    }
}
sub log4online{
    my $p_options=shift;
    my $checkonhit_fh=shift;
    my $p_check_res=shift;
    my $p_dotrue_res=shift; 
    my $hits=shift;
    my $round=shift;
    my $th=($hits==1)?('st'):
        ($hits==2)?('nd'):
        ($hits==3)?('rd'):('th');
    my $checkcmds=$p_check_res->[0];
    my $checkcmdsoutputs=$p_check_res->[1];
    my $dotruecmds=$p_dotrue_res->[0];
    my $dotruecmdsoutputs=$p_dotrue_res->[1];
    my $dotruecmdsoutputs_ori=$p_dotrue_res->[2];
    my $declare_hit="issue was hit (the $hits$th time) at the following commands after ($round) rounds";
    my $declare_check="following commands were checked right after the failure was detected";
    my $checkcmdsoutputs_pref=
                "\n"
                ."=" x (length $declare_hit)
                ."\n$declare_hit\n"
                ."=" x (length $declare_hit)
                ."\n"
                ;
    my $dotruecmdsoutputs_pref=
                "\n"
                ."=" x (length $declare_check)
                ."\n$declare_check\n"
                ."=" x (length $declare_check)
                ."\n";
    print $checkonhit_fh $checkcmdsoutputs_pref.$checkcmdsoutputs;
    print $checkonhit_fh $dotruecmdsoutputs_pref.$dotruecmdsoutputs;
    my $fault_len=length($checkcmdsoutputs_pref.$checkcmdsoutputs);
    my ($msgs_check,$msgs_dotrue,$msgs)=();
    $msgs_check=$p_options->{emailpref} 
        .$checkcmdsoutputs_pref     
        .$checkcmds;            
    if ($fault_len > 2*$p_options->{emailmax}){ 
        $msgs_check.=
            substr($checkcmdsoutputs,0,$p_options->{emailmax})  
            ."\n................snipped.................\n"
            .substr($checkcmdsoutputs,-$p_options->{emailmax})  
            ;
    }else{                      
        $msgs_check.=$checkcmdsoutputs;
    }
    if ($dotruecmdsoutputs_ori){    
        $msgs_dotrue=$dotruecmdsoutputs_pref
            .$dotruecmds
            ."\n\n\n\nthanks\nregards\nfrom remotecheck script"
            ;
    }else{              
        $msgs_dotrue="but nothing were found on further check!"
            ."\n\n\n\nthanks\nregards\nfrom remotecheck script"
            ;
    }   
    $msgs=$msgs_check.$msgs_dotrue;
    my @files=();
    push @files,($p_options->{checkonhit_file},$p_options->{checklog_file});
    if ($options{sendemail}){
        print "\nLOG4ONLINE: sendemail flag set, now send an email...\n";
        sendemail($p_options->{smtpserver},
            $p_options->{emailfrom},
            $p_options->{emailfakefrom},
            $p_options->{emailto},
            $p_options->{emailreplyto},
            $p_options->{emailsubj},
            $msgs,
            \@files) ;                          
    }
}
sub prehandle{  
    my $p_options=shift;
    my $p_cfgfopt=shift;
    my $p_difftime=shift;
    my $t=undef;
    my $host=$p_options->{host};                    
    print "\n\nPREHANDLE:#############preparing dir and files for logs and reports####################\n\n";
    $p_options->{log_dir_ori}           =   $p_options->{log_dir};
    $p_options->{checklog_file_ori}     =   $p_options->{checklog_file}; 
    $p_options->{checkonhit_file_ori}   =   $p_options->{checkonhit_file};
    print "Prehandle: backed up log_dir name base: $p_options->{log_dir_ori}\n";        
    print "PREHANDLE: backed up checklog_file name base: $p_options->{checklog_file_ori}\n";
    print "PREHANDLE: backed up checklog_file name base: $p_options->{checkonhit_file_ori}\n";  
    $p_options->{log_dir}=parsename(    $p_options->{log_dir_ori},
                                                                        $host );        
    if ( -e $p_options->{log_dir} ){
        print "PREHANDLE: Dir $p_options->{log_dir} exists...";
    }else{  
        mkdir( $p_options->{log_dir},07777 ) or die "can't make dir $p_options->{log_dir}!" ;
        print "PREHANDLE: Created a dir $p_options->{log_dir}...\n";
    }
    chdir( $p_options->{log_dir} );                 
    print "PREHANDLE: Enter dir $p_options->{log_dir}...\n";
    $p_options->{checklog_file}=parsename($p_options->{checklog_file_ori},$host);
    print "PREHANDLE: get a file name for checklog_file base: $p_options->{checkonhit_file_ori}\n";
    if ($p_options->{online}){                      
        print "\nPREHANDLE: online set,login ...\n";        
        if (exists                                  
                $p_cfgfopt->{logininfo}{hash}{"$host"}
            ){          
            $t=login(   $p_cfgfopt->{logininfo}{hash}{"$host"},
                                $p_options  );
            $p_options->{telnet_obj}    =   $t;     
        }else{                                      
            die "\nPREHANDLE: there is no information configured for $host under logininfo clause inside config file $p_options->{config_file}!\nplease double check!\n";       
        }
        $t->cmd("term len 0");                      
        if ($p_options->{timing}=~/remote/){
            my $localtime=localtime;                
            my ($remotetime)=$t->cmd("$p_options->{clock_cmd}");        
            print "\nPREHANDLE: time calculation..." if ($p_options->{debug});
            print "\nPREHANDLE: localtime now is:$localtime\n", if ($p_options->{debug});
            print "\nPREHANDLE: remotetime now is:$remotetime\n", if ($p_options->{debug});
            @$p_difftime=time_diff($localtime,$remotetime);     
            time_diff_print($p_difftime,$p_options->{debug});   
        }
        $p_options->{checklog_file}=parsename(  $p_options->{checklog_file_ori},
                                                $host,
                                                0,
                                                $p_options->{timing},$p_difftime);
        print "\nPREHANDLE: get a new (w/ updated timing) name for checklog : $p_options->{checklog_file}\n";
=pod        
        $t->close;
        $t=login($p_cfgfopt->{logininfo}{hash}{"$host"},$p_options);
        $p_options_run->{telnet_obj}=$t;
        $t->cmd("term len 0");  
=cut        
        print "\nPREHANDLE: use new checklog file name $p_options->{checklog_file} for current session\n";
        $p_options->{checklog_file_fh}=$t->input_log($p_options->{checklog_file});
        $p_options->{checkonhit_file}=parsename($p_options->{checkonhit_file_ori},
                                                $host,
                                                0,
                                                $p_options->{timing},$p_difftime);
        print "\nPREHANDLE: prepared a checkonhit file: $p_options->{checkonhit_file}\n";
        open my $checkonhit_fh, '>>', $p_options->{checkonhit_file}     
            or die "\nRUN: Could not open $p_options->{checkonhit_file}";
        $|=1;
        $p_options->{checkonhit_fh_online}=$checkonhit_fh;
        if (!$p_options->{cli_prompt}){
            $p_options->{cli_prompt}=cli_prompt($t,
                                       'pwd',
                                       $p_options->{debug});
        }
        return $checkonhit_fh;              
    }else{
        print "\nPREHANDLE: online not set,will parse cmd log file: $p_options->{cmdlog_file}\n";
        print "PREHANDLE: creating checklog file(output): $p_options->{checklog_file}\n";
        open my $checklog_fh_offline, '>>', $p_options->{checklog_file} 
        or die "PREHANDLE: Could not open $p_options->{checklog_file}";
        $p_options->{checklog_fh_offline}=$checklog_fh_offline;
        return $checklog_fh_offline;        
    }
}
sub log4offline{
    my $checklog_fh=shift;
    my $p_check_res=shift;
    my $p_dotrue_res=shift;
    my $p_dofalse_res=shift;
    my $checkcmdsoutputs=($p_check_res->[1])?($p_check_res->[1]):('');
    my $dotruecmdsoutputs=($p_dotrue_res->[1])?($p_dotrue_res->[1]):('');
    my $dofalsecmdsoutputs=($p_dofalse_res->[1])?($p_dofalse_res->[1]):('');
    my $checklog_offline=$checkcmdsoutputs.$dotruecmdsoutputs.$dofalsecmdsoutputs;
    print $checklog_fh $checklog_offline;
}
sub checkoptions4run{
    my $p_options=shift;
    my $p_cfgfopt=shift;
    my $host=$p_options->{host};
    $p_options->{hostdataclause}='';            
    if($host){                                      
        foreach my $clausename (keys %$p_cfgfopt){  
            if (
                ($clausename=~/data\s*$host/)       
                or                                  
                ($clausename=~/data\s*all\s*$/i)    
                or                                  
                ($clausename=~/data\s*$/i)          
               ){                                   
                $p_options->{hostdataclause} = $clausename;
            }
        }
        if($p_options->{hostdataclause}){       
            return 1;                               
        }else{                                      
            print "\nCHECKOPTIONS: there is no information configured for $host under any data clause inside config file $p_options->{config_file}!\n";
            print "CHECKOPTIONS: please double check your config_file!\n";
            return 0;
        }
    }else{                                          
        print "CHECKOPTIONS4RUN:no host has been defined,please specifiy one\n\n";
        return 0;
    }
}
sub lr_time{        
    my $timing=shift;
    my $p_difftime=shift;
    my $rtimetype=$p_difftime->[0]; 
    my $dseconds=$p_difftime->[1];  
    return
    ($timing=~/local/)?localtime:
    ($rtimetype eq 'local')?(localtime(timelocal(localtime)+$dseconds)):
    (gmtime(timegm(gmtime)+$dseconds)." GMT");
}
sub parsename{
    my $name_ori=shift; 
    my $host=shift;     
    my $force=shift;    
    my $timing=shift;   
    my $p_difftime=shift;   
    return ($timing)?(addtime   
                ( addhost($name_ori,$host),
                $force,
                $timing,
                $p_difftime)
             ):
            (addtime    
                ( addhost($name_ori,$host)
                )
            );
}