#!/usr/local/bin/perl
#remotecheck: a script to implement the following task:
# login a host and 
# capture information
# analyze commands outputs
#   currently it uses a config file to configure itself
#   allow user to capture the interested values out of
#   CLI output (both from online or from offline file like showtech)
#   and then based on that it allow user-defined behavior
#   such as alarming or further check with other commands.
#   
#################################################################
###############some progma settings##############################
#################################################################
#BEGIN {
#   push @INC,'/home/ping/.cpan';
#}               
                #more portable on other systems while downloading/installing
                #modules are having issues.
                #need to copy all module files *.pm into ./module dir
                #this is tested and worked great for cygwin , solaris
#use lib '/home/ping/.cpan';	#this is another solution for modules
use warnings;       
use diagnostics;       #turn this off when script finalizes
use strict;

###testing code###
print "\nthis OS is detected as: $^O\n";
#exec "ls\n";
#fork;
print "\nCurrent PID is: $$\n";

#################################################################
#####################loaded modules##############################
#################################################################

print @INC;

use Net::Telnet ();     #for telnet connections to check online
                #  only load methods and no functions
use IO::Tee;            #trial, need install
                #  can print log to multiple places(say,both stdout and logfile)
use FindBin qw($Bin);       #trial, core module
                #  provide current working dir
use lib $Bin;           #indicating what modules being used are all under current dir
use Cwd;            #same as $Bin in FindBin

use File::Spec;         #portable module for file/dir operation
use File::stat qw(:FIELDS);
use File::Copy;

use Data::Dumper;       #use this module to print complex data structure

#use YAML;          #this is more compact,but less aligning

#use Tie::IxHash;       #initially hope to use this to make print Dumper print
                #the hashes in the order when they are inputed, not working
                #as expected

use Mail::Sender;       #send smtp email
        
use Getopt::Long;       #command line options

use Array::Compare;     #to compare arrays (cmds outputs)

#use List::Util qw(first max maxstr min minstr reduce shuffle sum);
                #only use the max/min function, not in use
#use Date::Calc qw(:all);   #use to calculate time difference
                #between local & remote machine,not in use
use Time::ParseDate;

use Time::Local;

use Archive::Zip qw( :ERROR_CODES :CONSTANTS );

use Term::ShellUI;

#use mylib69;           #load defined module
#use cfgfparse69;       #load defined module

#################################################################
#######################global vars or constants##################
#################################################################

my %cfgfopt;                    #data structure read from cfgfile

my (%precheckdata,%precheckcmdsoutputs);    #hash of cmdsoutputs and captured data
my (%olddata,%oldcmdsoutputs);
my (%checkdata,%checkcmdsoutputs);
my (%dotruedata,%dotruecmdsoutputs);
my (%dofalsedata,%dofalsecmdsoutputs);
my (%postcheckcmdsoutputs,%postcheckdata);

my (%options,%options_cli);         #used to store all options got from cli

#tie %cmdsoutputs, "Tie::IxHash";
#tie %cfgfopt, "Tie::IxHash";
#tie %data, "Tie::IxHash";

# my $checkonhit;               #all checkonhit found will be print to this scalar
# my $checklog_fh;          #offline mode checking log put into this file
                    #(mostly for function test offline)

my ($normal,$verbose,$extensive);
my ($scriptname_ori,$scriptname,$scriptname_dir,$scriptname_cfg);


#some parameters are based on script running name
$scriptname_cfg=$scriptname_dir=$scriptname_ori=$scriptname=$0; 

$scriptname=~s/\.\///;              #for script name: remove possible "./xxx"
$scriptname=~s/(.*?)\.\w+$/$1/;         #    then use anything bef the suffix (.pl/.exe)
$scriptname_cfg=~s/(.*?)\w+$/$1cfg/;        #replace suffix with .cfg,as def config_file name
$scriptname_dir=$scriptname;            #use scriptname as default dir for logs

my ($dec_array,$dec_scalar,$dec_scalar_all,$print_test,$checkdata)=();
                        #store dynamic code for eval
my $scalar_setflag;             #store dynamic code for eval

#my $checkcmdsoutputs_pref,$dotruecmdsoutputs_pref; #some words/notes in log file/emails 


my $interupted=0;               #flag to indicate if we are being interupted

my %options_def=(
            help        => 0,
            usage       => 0,
            
            shell       => 0,            	#def not shell mode
            history_shell => "history_shell.txt",
                                        	#default file name to story history shell cmds
                                        
            online      => 0,           	#def offline
            rounds      => 1_000_000_000,   #def 'almost' forever (if under online mode)
            sleep       => 10,				#def sleep 10s between every batch of CLIes
            debug       => 0,				#def no debug

        #   SOME USEFULL OPTIONS:       
            config_file => "$scriptname_cfg",   #
            log_dir     => "$scriptname_dir",   #
            checklog_file   => "remotechecklog%h%t.txt",#
            cmdlog_file => "show tech.txt", #
            checkonhit_file => "checkonhit%h%t.txt", 
            timing      => "local",
            clock_cmd   => "show clock",    #command used to take remote clock
            telnet_timeout  => 60,
            telnet_buffer   => 8_000_000,
            init_prompt => '/[\$%#>]\ ?$|login: $|password: $|username: $/i',
            ziplog      => 1,
            size2zip    => 10_000_000,

        #   email settings  
            sendemail   => 0,           #don't send email
            smtpserver  => "smtp.sina.com.cn",  
            emailfrom   => "routermonitor <routermonitor\@sina.com>",
            emailfakefrom   => "routermonitor <routermonitor\@ericsson.com>",
            emailto     => "ericsson team <routermonitor\@sina.com>",
            emailreplyto    => "ericsson team <routermonitor\@sina.com>",
            emailsubj   => "failure report",
            emailpref   => "the issue were detected,for more info please see attachments.\n info collected at the failure point:\n\n\n",
            emailmax    => 600,

            repeat      => 1,           #repeat mode
            times       => 1,

        );

use constant USAGEMSG2 => << 'USAGE-END2';
logtool version 0.9x.
author: song ping <ping.song@ericsson.com>
bug report is welcome.
copyright 2009

usage:
    #help and usage
    logtool -help           #more detail instructions
    logtool -usage          #this message, brief usage
    
    #run in shell mode (unix style,more friendly,recommended mode)
    #set up options,review or modify it,then run it
    logtool -shell [OPTIONS]
    
    #run in CLI option mode
    #provide all options and run it all in one go
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
logtool version 0.9x.
author: song ping <ping.song@ericsson.com>
bug report is welcome.
copyright 2009

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


#################################################################
#######################main codes###############################
#################################################################
# print "\nMAIN: command read: \n[$0 @ARGV]\n";     #echo the CLI for debug

checkoptions4cli(\%options,                     #check options from: def->env->cfg->cli
                \%options_cli,
                \%options_def,
                \%cfgfopt);
                
cfgfparse2(\%cfgfopt,                           
            $options{debug});                   #config file parsing stageII
            

$SIG{INT}=\&interuption_handler;                #ctrlC interception handler

my $term;

if ($options{shell}){                           #shell mode if '-shell' is enabled
    $term = new Term::ShellUI(
        commands => get_commands(),
    #   history_file => '~/.shellui-history',
        history_file => "$options{history_shell}",      
    #          prompt => "remotecheck>",
    );

#   print 'Using '.$term->{term}->ReadLine."\n";
    print "\n(you are now running under UNIX-style shell mode)\n";
    print "Tab to complete,^C to stop \'run\',exit|quit|bye to exit\n";
#    $term->prompt( sub{"$scriptname"            #shell prompt
#                    . " [" 
#                    . $term->{term}->GetHistory() 
#                   . "]" 
#                   . " >> " } );

    $term->run();                               #under shell mode (wait for cmds)
    
#   print "MAIN: options from shell are:\n",Dumper(\%options) if ($options{debug}==3);

}else{                                          #run the check if '-shell' not given
    run ();                                     #(CLI mode)
}

################################################################################
########################functions###############################################
################################################################################




sub run{
    # $p_options->{hostdataclause}
    #   $p_options->{checklog_fh_offline}
    #   $p_options->{checkonhit_fh_online}
    #   $p_options->{telnet_obj}
    #   $p_options->{checklog_file_ori}
    #   $p_options->{checkonhit_file_ori}                                               

    my @difftime=();
    my $hits=0;                     #setup a counter for time of hit
    clear_interuption();                        #clear the interuption bit
    return unless ( checkoptions4run(\%options, #check options before "run"
                                    \%cfgfopt,
                                )
                    );
                                                #check options required to run the check
                                                #print msg if some options need to be set
                                                #ref: 
                                                #   $p_options_run->{hostdataclause}
                            
    chdir($Bin);                    #always start working under base working dir

    ##debug settings (for backward compatibility to old codes)
    $normal=$options{debug} 
        if ( $options{debug}=~/normal/ or $options{debug}=~/1/);
    $verbose=$options{debug} 
        if ($options{debug}=~/verbose/ or $options{debug}=~/2/);
    $extensive=$options{debug} 
        if ($options{debug}=~/extensive/ or $options{debug}=~/3/);
    
    #some prehandlings before checking:
    #create DIRs for logs,change into it, prepare telnet obj for online mode
    #create logfiles, calculate time different for remote timing mode
    #capture telnet prompt
    #return:
    # fh of checkonhit_file(online) or checklog(offline)
    #new entries:
    #   $p_options->{checklog_fh_offline}
    #   $p_options->{checkonhit_fh_online}
    #   $p_options->{telnet_obj}
    #   $p_options->{checklog_file_ori}
    #   $p_options->{checkonhit_file_ori}
    #
    prehandle(  \%options,
                \%cfgfopt,
                \@difftime) 
            or die "RUN: file operation problem within PREHANDLE procedure\n";  
    print "\n\nRUN: data parsing\n\n" if ($options{debug});
    
    my $host=$options{host};                    #which host we're going to check
    
    my $dseconds=$difftime[1];                  #get the time difference
    my $hostdataclause=$options{hostdataclause}; #which clause we're going to use   
    
    if (exists ( $cfgfopt{"$hostdataclause"}{precheck} ) ){
        print "\nRUN: precheck configured, do prechecking...\n";
        dataparse(                              #perform prechecking if configured
                    \%options,
                    $cfgfopt{"$hostdataclause"}{'precheck'},
                    \%precheckcmdsoutputs,
                    \%precheckdata,
                    \@difftime);
    }                   
    
    #auditing codes
    audit();                                    #dealing with perlhandle&simplereport clauses
    
    if ( exists ( $cfgfopt{"$hostdataclause"}{check} ) ){   #start check loop when check block exists
                                
        my $temp=-s $options{checklog_file};
        print "\nRUN: checklogfile before check stage is: $options{checklog_file} ($temp Byte)\n";

        print "\nRUN: check block configured,go check them in loop...\n";
    
        #statements and the result after processing these statements
        my ($checkstate,$checkchange,$checkfinal,$checkstate_res,$checkchange_res,$checkfinal_res)=();
        $checkstate=$cfgfopt{"$hostdataclause"}{hash}{checkstate};  
        $checkchange=$cfgfopt{"$hostdataclause"}{hash}{checkchange};    
        $checkfinal=$cfgfopt{"$hostdataclause"}{hash}{checkfinal};  
    
        #check for the 1st time,this is to setup a data base for "compare" statement
        dataparse(
                    \%options,
                    $cfgfopt{"$hostdataclause"}{'check'},
                    \%oldcmdsoutputs,
                    \%olddata,
                    \@difftime);

        $temp=-s $options{checklog_file};
        print "\nRUN: checklogfile after 1st check stage is: $options{checklog_file} ($temp Byte)\n";

        
        ##generate dynamic codes to be evaled: get all declarations
        ($dec_array,$dec_scalar)=( actionparse( \%olddata,
                                                "olddata",
                                                $options{debug})
                                 )[0,1];
    
        
        #data before(check)/after(dotrue) issue was hit:
        #   record the: commands and outputs(xxxoutputs_ori)
        #   also reformat the outputs(xxxoutputs) ,more readable

        my (@check_res,@dotrue_res,@dofalse_res)=();
                
        ######################round loop checking######################
        for(    my $round=1;
                (   ($round<=$options{rounds})  #continue looping if rounds not finished
                    &&                          #and 
                    not $interupted             #not interupted by user (e.g. by Ctrl-C)
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
                        \@difftime);    #run the check blocks                   

            $temp=-s $options{checklog_file};
            print "\nRUN: checklogfile after $round round check stage inside the loop is: $options{checklog_file} ($temp Byte)\n";

            #re-format the cli & its outputs
            cmdsoutputs_format(\%checkcmdsoutputs,\@check_res);
            
            #get all captured data:
            my ($checkdata) =   (actionparse(   \%checkdata,
                                                "checkdata",
                                                $options{debug})
                                )[4];
            
            print "\nRUN: the \$checkdata we got now is:\n[\n$checkdata\n]\n" if ($extensive);
            
            #get all flags per the data comparision (changed or not yet)
            $scalar_setflag=datacompare(\%checkdata,
                                        \%olddata,
                                        $options{debug});
                    
            #truefalse calculation
            my $truefalse=rulecalc( $checkstate,
                                    $checkchange,
                                    $checkfinal,
                                    $dec_array,
                                    $dec_scalar,
                                    $scalar_setflag,
                                    $checkdata,
                                    $options{debug});
                                        
            #force the check flow if configured via param: dotrue | dofalse 
            $truefalse=$options{truefalse} if (exists $options{truefalse});
            
            #save current checkdata for comparision on next round
            %olddata=%checkdata;            
    
            ##check the dotrue block if:
            ##  we did captured sth as a result of the 'checkstate' statement execution, or
            ##  we detected anything changed as a result of 'checkchange'
            ##check dofalse block otherwise
            if ($truefalse){            #if we detected the condition
                                #then perform the dotrue parts
                ++$hits;            #increase the $hits counter
                my $th=	($hits==1)	?	('st'):
                    	($hits==2)	?	('nd'):
                    	($hits==3)	?	('rd'):
                    					('th');
                
                print "\nRUN: <=====looks we detected the issue (the ${hits}$th time) here! check dotrue commands..\n";
    
                if (exists($cfgfopt{"$hostdataclause"}{dotrue})){   #if dotrue commands exists,run them
                    print "\nRUN: dotrue blocks configured,now check them\n";
                    
                    #check the dotrue blocks
                    dataparse(
                                \%options,
                                $cfgfopt{"$hostdataclause"}{'dotrue'},
                                \%dotruecmdsoutputs,
                                \%dotruedata,
                                \@difftime);
                    
                    $temp=-s $options{checklog_file};
                    print "\nRUN: checklogfile after $round dotrue stage inside the loop is: $options{checklog_file} ($temp Byte)\n";

                    #re-format the dotrue outputs
                    cmdsoutputs_format(\%dotruecmdsoutputs,\@dotrue_res);
                    
            #       print $tee_fh $writeonhit;  #print to both $checkonhit and $checkonhit_file
                    
                    #write to a file and prepare an email
                    log4online( \%options,
                                $options{checkonhit_fh_online},
                                \@check_res,
                                \@dotrue_res,
                                $hits,
                                $round);
                    
                }else{      #otherwise if no dotrue configured, goback do check blocks again
                    print "\nRUN: <=====dotrue blocks not conigured,redo check block\n";
                }
    
            }else{          #otherwise if we found nothing,then everything is fine, do dofalse blocks
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
    
            } #end of truefalse
    
            #sleep for conigured seconds between each round
            if ($options{sleep}){   #$sleep is got from main.
                print "\n        nRUN: sleep for $options{sleep}s at end of round($round)...\n";
                if ($hits){
                    print "\nRUN: so far the issue has been hit $hits times!\n" ;
                }else{
                    print "\nRUN: so far the issue hasn't appeared again...\n";
                }
                sleep $options{sleep};  #sleep for a while between each round
            }
            
            #log on offline mode
            
            log4offline(    $options{checklog_fh_offline},
                            \@check_res,
                            \@dotrue_res,
                            \@dofalse_res) 
                        unless ($options{online});
            
            ####periodically check generated files and zip accordingly
            if ($options{ziplog}){
                print "\nRUN: ziplog set, checking and zip big log files...\n";
                zipbigfile(\%options,\@difftime);
            }
            
            my $temp=-s $options{checklog_file};
            print "\nRUN: checklogfile is now: $options{checklog_file} ($temp Byte)\n";
                            
        } #end of rounds loop
        
        if (exists($cfgfopt{"$hostdataclause"}{postcheck})){    #do postchecking if configured
            print "\nRUN: postcheck configured, do postchecking...\n";
            dataparse(
                        \%options,
                        $cfgfopt{"$hostdataclause"}{'postcheck'},
                        \%postcheckcmdsoutputs,
                        \%postcheckdata,
                        \@difftime);
        }
        
        #close the telnet session if it was opened
        print "\nRUN: tear down telnet sessions...\n";
        $options{telnet_obj}->close if ($options{telnet_obj});  
        
    }else{      #if no 'check' statements in data clause, no need to loop
        print "\nRUN: there is no check blocks conigured\n";
    } #end of all check codes
    
    #restore dir base backup log file name base
    $options{log_dir}                   =   $options{log_dir_ori};
    $options{checklog_file}     =   $options{checklog_file_ori}; 
    $options{checkonhit_file}   =   $options{checkonhit_file_ori};
    print "Prehandle: restored log_dir name base: $options{log_dir_ori}\n";     
    print "PREHANDLE: restored checklog_file name base: $options{checklog_file_ori}\n";
    print "PREHANDLE: restored checklog_file name base: $options{checkonhit_file_ori}\n";   
            
    chdir($Bin);    
    print "\nRUN: go back to working DIR $Bin\n";
}
################################################################################
################################################################################
######################cfgfparse.pm:  cfg file reading###########################
################################################################################
################################################################################

#these functions parses the config file and organize the info into the cfgfopt hash

sub cfgfparse{  #this function focus on:
        #   pre-handling (removing comments/handle readfrom file)
        #   general handling (clause and hash the config)
        #configuration file ==> %clauses
        #param1: config file name
        #param2: ref to \%cfgfopt structure
        #param3: debugmode
        #
    my $cfgfname=shift;
    my $p_cfgfopt=shift;
    my $debugmode=shift;
        my ($normal,$debug,$extensive);
    
#   print "CFGFPARSE: inside cfgfparse,params: $cfgfname $debugmode \n";
    if ($debugmode){
        $normal=$debugmode if ($debugmode=~/normal/ or $debugmode=~/1/);
        $debug=$debugmode if ($debugmode=~/debug/ or $debugmode=~/2/);
        $extensive=$debugmode if ($debugmode=~/extensive/ or $debugmode=~/3/);      
    }
                    
    #############config file options###############

    my ($globalsettings,$online,$logfile);      #GlobalSettings clause,online option
    my ($logininfo,@login_cmds);
    my $data;                   #content of data clause 
    my ($perlhandle,$simplereport);         #action codes

    #############config file reading, removing comments###############
    my $cfgfh;
    open $cfgfh, "+<", $cfgfname or die $!;     
    
    print "\nCFGFPARSE: config file $cfgfname opened for read...\n" if ($debugmode);
    $|=1;
    print "\nCFGFPARSE: reading cfg file ...\n" if ($debugmode);
    
    print "\nCFGFPARSE: removing comments...\n" if ($debugmode);
    my $cfgfile=join '',<$cfgfh>;       #join array into one string
    $cfgfile=~s/((?:\s+)|^)#.*/$1/g;    #remove commented part
#   $cfgfile=~s/(?=^(?:(?!\".*?#.*?\"\s*;).)*$)((?:\s+)|^)#.*/$1/g; 
#   $cfgfile!~/\".*#/
    $cfgfile=~s/^\s*\n//mg;         #remove any pure blank lines
    
    print "\nCFGFPARSE: the valid config read as following:\n[\n$cfgfile\n]\n" if $extensive;
    
    print "\nCFGFPARSE: configuration file parsing start:phase I...\n" if ($debugmode);
    
    #########split cfgfile into clause==>content hash################
    print "\nCFGFPARSE: parsing step1 (->claused)...\n" if ($debugmode);
    my %clauses=($cfgfile=~/<(.*)>(.*?)<\/\1>/sig);
    foreach (keys %clauses){
        my $old=$_;
        s/(.*)/\L$1/;           #change all clause name into low case
        $p_cfgfopt->{$_}{'clause'}=$clauses{$old};
    }
    print "\nCFGFPARSE: parsed step1 (=>claused) %cfgfopt looks:\n",Dumper($p_cfgfopt) if $extensive;

    ##########split each clauses into key==>value hash##################

    print "\nCFGFPARSE: parsing step2 (=>hashed) ...\n" if ($debugmode);            
    foreach (keys %$p_cfgfopt){                     #for each clausename
        my $clausename=$_;
        my $clausevalue=$p_cfgfopt->{$clausename}{'clause'};        #get the clause strings
        print "\nCFGFPARSE: current clause is:[$clausename]\n" if ($debug or $extensive);
                        
        my %keyvalue=($clausevalue=~/^\s*?(\S+)\s*(.*?)\s*$/mig);   #split into key-string pairs
        my @cliseq=($clausevalue=~/^\s*?\S+\s+\S+\s*=\s*{\s*(\S.*?\S)\s*}/mig);
                                        #for data clause,retain the cli sequence
        print "\nCFGFPARSE: cli sequences are:@cliseq\n" if ($debug or $extensive);
        my $clausevaluefromfile=readfrom2($keyvalue{'readfrom'});   #now try check the 'readfrom' keyword
                                        #if a valid file is configured,
                                        #read values from it
                                        
        if ($clausevaluefromfile){              #if 'readfrom' file contains anything
            print "\n   CFGFPARSE: returned value from data file is:\n$clausevaluefromfile\n" if ( $debug or $extensive);
#           $clausevalue=$clausevaluefromfile;          
            print "\n   CFGFPARSE: update the original clause...\n" if ( $debug or $extensive);
            $p_cfgfopt->{$clausename}{'clause'}=$clausevaluefromfile;   #override the orig clause
            print "\n   CFGFPARSE: re-parsing the new clause...\n" if ( $debug or $extensive);
            %keyvalue=($clausevaluefromfile=~/^\s*?(\S+)\s*(.*?)\s*$/mig);  #redo key-string pairs spliting 
        }else{
            print "\n   CFGFPARSE: nothing contained in data file!" if ( $debug or $extensive);
        }
        
#       print "\nthe key==>value pair for clause $clausename looks:\n",Dumper(\%keyvalue) if $debug;

        print "\n   CFGFPARSE: attach the parsed result into cfgfopt\n" if ($debug or $extensive);
        foreach (keys %keyvalue){                   #attach key-string pairs to cfgpopt
            my $oldkey=$_;
            s/(.*)/\L$1/;                       #convert any key into lower case
#           $p_cfgfopt->{$clausename}{'hash'}{$key}=$value;
            $p_cfgfopt->{$clausename}{'hash'}{$_}=$keyvalue{$oldkey};
        }
        
        $p_cfgfopt->{$clausename}{'commands'}=\@cliseq;
    }
    
    print "\nCFGFPARSE: parsed step2 (->hashed) %cfgfopt now looks:\n",Dumper($p_cfgfopt) if $extensive;
    print "\nCFGFPARSE: configuration file parsing done:phase I...\n" if ($debugmode);

}
    
sub cfgfparse2{     #this function deal with sepcial handlings for some clauses
            #param:ref to cfgfopt
            #param:debugmode
            
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
    if (0==keys %$p_cfgfopt){   #if nothing a/v in cfgfopt (cfg reading fail),simply return
        print "\nCFGFPARSE2: no config file, skipping configuration file parsing stage II...\n";
        return ;
    }
    
    my ($logininfo_readfrom,$data_readfrom);
    my ($wanted,$cli,$ptn1,$ptn2);

    print "\nCFGFPARSE2: configuration file parsing start:phase II...\n" if ($debugmode);
    
    #####################1. parsing login infos#####################    
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
    

    #####################2. parsing data #####################      
    print "\nCFGFPARSE2: step4 parsing data clause...\n" if ($debugmode);   
    my $datatype;
    my (%cmdseq,$seq);
    foreach my $clausename (keys %$p_cfgfopt){  #get each clause name
        if ($clausename=~/data/){       #if it's data clause
                            #parse those precheck/check/dotrue/dofalse part/postcheck       
            print "\nCFGFPARSE2: step4 parsing ($clausename=>datatype,cli,wanted)...\n" if ($debugmode);    
            
            foreach (keys %{$p_cfgfopt->{"$clausename"}{'hash'}}) {
                            #for each hash entry
            ####################2.1 parsing precheck/check/dotrue/dofalse/postcheck#####################            
                            
                $datatype=(/precheck/)?('precheck'):        #get datatype
                    (/dotrue/)?('dotrue'):
                    (/dofalse/)?('dofalse'):
                    (/postcheck/)?('postcheck'):
                    (/^check\d+/)?('check'):
                    (/checkstate/)?('checkstate'):
                    (/checkchange/)?('checkchange'):
                    (/checkfinal/)?('checkfinal'):
                    ('');                   #mark as '' for unsupported 
                    
                                        #get seq number
                ($seq)=/(\d+)/ if /\d+/; #for precheck/check/dotrue/dofalse/postcheck
                $seq=0 unless /\d+/;     #for checkfinal/checkstate/checkchange
                                
                print "\nCFGFPARSE2: seqnum in $_ is $seq\n" if ($debug or $extensive);
                
                if ($debug or $extensive){
                    print "\nCFGFPARSE2: datatype $datatype\n" if ($datatype);
                    print "\nCFGFPARSE2: unsupported datatype:$_\n" unless ($datatype);
                }
                next if (/checkstate/ or /checkchange/ or /checkfinal/); 
                                        #skip on checkstate/change/final
                next unless ($datatype);            #skip on un-supported data
        
                
                my $dataline=$p_cfgfopt->{"$clausename"}{'hash'}{$_};       
                if ($dataline=~/\S/) {
                    print "\n  CFGFPARSE2: one $datatype line is:\n  [\n  $dataline\n  ]\n" if ($debug or $extensive);
                    ($wanted,$cli,$ptn1,$ptn2)=
                                ($dataline=~(/
                                        \s*
                                        (\w+)       #wanted value
                                        \s*
                                        =       #=
                                        \s*{\s*
                                            (.*?)   #cli
                                        \s*}\s*
                                        (?:
                                            (?:     #either followed by ptn(s)
                                            :       #:
                                            \s*{\s*
                                                (.*?)   #ptn1
                                            \s*}
                                            (?:     #ptn2 or nothing
                                                :
                                                \s*\{\s*
                                                    (.*?)   #ptn2
                                                \s*\}\s*
                                            |           #or...
                                            \s*         #nothing
                                            )
                                            )
                                            |       #or
                                            \s*     #no ptns at all
                                        )
                                      /x)
                                );
        #           $ptn2=(defined($ptn2))?$ptn2:'';
                    print "  CFGFPARSE2: from cli:[$cli]\n   the wanted is:[$wanted]\n" if ($extensive and defined($ptn2));
                    $ptn1?print "\n    CFGFPARSE2: ptn1 is:$ptn1\n":print "\n    CFGFPARSE2: ptn1 undefined\n" if ($debug or $extensive);
                    $ptn2?print "\n    CFGFPARSE2: ptn2 is:$ptn2\n":print "\n    CFGFPARSE2: ptn2 undefined\n" if ($debug or $extensive);


                    $p_cfgfopt->{"$clausename"}{$datatype}{$cli}{$wanted}=[$ptn1,$ptn2];
                    $cmdseq{$datatype}{$seq}=$cli;
        #           print "\n  CFGFPARSE2: cmdseq is: $datatype->$seq->$cli\n";
                }
                
            } #each entries of {"$clausename"}{'hash'}

            print "\nclause $clausename commands are tagged as following\n",Dumper(\%cmdseq) if ($extensive);
            foreach my $datatype (keys %cmdseq){            #foreach datatype
                foreach my $seqnum (                #get the seq num
                            sort {$a <=> $b} (keys %{$cmdseq{$datatype}})
                            ){              #sort the seq num   
                                        #then push the cli per sorted seq       
        #           print "\nthe cli for seq num $seqnum is:$cmdseq{$datatype}{$seqnum}\n";
                    push @{$p_cfgfopt->{"$clausename"}{$datatype}{commands}},$cmdseq{$datatype}{$seqnum};
                }
                print "\nnow the $datatype are sorted as following\n          $datatype=> \n",Dumper($p_cfgfopt->{"$clausename"}{$datatype}{commands}) if($extensive);
            }
            

            
            ##############2.2 replace the checkstate/comp/final to perl executable ##############       

            print "\nCFGFPARSE2: step4 parsing ($clausename: checkstate/checkchange/checkfinal)...\n" if ($debugmode);  
            my $checkstate=$p_cfgfopt->{"$clausename"}{hash}{checkstate};   
            my $checkchange=$p_cfgfopt->{"$clausename"}{hash}{checkchange}; 
            my $checkfinal=$p_cfgfopt->{"$clausename"}{hash}{checkfinal};   
            
            if ($checkstate){               #check and process checkstate config if configured
                print "\$checkstate configured as: $checkstate\n" if ($verbose or $extensive);      
                $checkstate=~s/(\w+)/\@$1/g;        
                $checkstate=~s/ @(or|and) / $1 /g;  
                $checkstate=~s/\s*\@not /not /g;        #convert $checkstate to perl

            }else{
                $checkstate='';
            }

            if ($checkchange){              #check and process checkchange config if configured
                print "\$checkchange configured as: $checkchange\n" if ($verbose or $extensive);
                $checkchange=~s/(\w+)/\$$1/g;
                $checkchange=~s/ \$(or|and) / $1 /g;
                $checkchange=~s/\s*\$not /not /g;
            }else{
                $checkchange='';
            }

            if($checkfinal){                #check and process checkfinal config if configured
                                    #if checkfinal configured,then both checkstate and
                                    #checkchange should be already configured
                print "\$checkfinal configured as: $checkfinal\n" if ($verbose or $extensive);
                $checkfinal=~s/(\w+)/\$$1_res/g;    #change all bareward to var,append _res
                $checkfinal=~s/ \$(or|and)_res / $1 /g; #recover back operator or|and
                $checkfinal=~s/\s*\$not_res /not /g;    #recover back operator not
            }else{
                $checkfinal='';
            }
            $p_cfgfopt->{"$clausename"}{hash}{checkstate}=$checkstate;
            $p_cfgfopt->{"$clausename"}{hash}{checkchange}=$checkchange;
            $p_cfgfopt->{"$clausename"}{hash}{checkfinal}=$checkfinal;
        
        }   #if ($clausename=~/data/)
        

    } #foreach clausename
    print "\nCFGFPARSE2: configuration file parsing done:phase II...\n" if ($debugmode);
    print "\nCFGFPARSE2: the final parsed %cfgfopt now looks:\n",
        Dumper(\%cfgfopt) if $extensive;
}

sub readfrom{           #this function deal with readfrom function for each clause
                #param1:ref to %cfgfopt
                #param2:
    my $p_cfgfopt=shift;
    my $clausename=shift;
    
    my $clausevalue;
        
    my $readfrom=$p_cfgfopt->{$clausename}{'hash'}{'readfrom'};
#   print "\nREADFROM: inside readfrom function\n";
    print "\nREADFROM: clause $clausename configured readfrom value: $readfrom\n" if defined $readfrom;
    return unless $readfrom;
    
    if ($readfrom=~/\s*(\w+\.?\w*)\s*/){                #if readfrom a filename abc.123
        print "\nREADFROM: readfrom configured as file $1\n";
        $readfrom=$1;
        if (-f $readfrom){
            open my $datafh, "+<", $readfrom or die "READFROM: open file $readfrom for clause $clausename failed: $!\n";
            print "\nREADFROM: READFROM: file $readfrom opened for read...\n";
            $|=1;
            print "\nREADFROM: reading data file ...\n";

            $clausevalue=join '',<$datafh>;         #join array into one string
            $clausevalue=~s/#.*\n/\n/g;         #remove commented part
            $clausevalue=~s/^\s*\n//mg;         #remove any pure blank lines

            return $clausevalue;
        }else{
            print "\nREADFROM: file $readfrom does not exist!\n";
        }

    }elsif ($readfrom=~/^\s*\.\s*$/){               #if readfrom .
        print "\nREADFROM: readfrom configured as current config file(.)\n";
    }else{
        print "\nREADFROM: illegal filename $readfrom!\n";
    }
}


sub readfrom2{          #this function deal with readfrom function for each clause
                #param1:the readfrom strings
    my $readfrom=shift;
    
    my $clausevalue;
        
#   print "\ninside readfrom function\n";
    print "\n   READFROM2: configured readfrom value: $readfrom" if defined $readfrom;
#   return unless $readfrom;
    if (not defined $readfrom){
        
    }elsif ($readfrom=~/\s*(\S+\.?\w*)\s*/){            #if readfrom a filename abc.123
    #   /\s*(\S+)\s*/   #seems this one is enough?
        print "\n   READFROM2: the readfrom file configured as: $1";
        $readfrom=$1;
        if (-f $readfrom){  #if file exist
            open my $datafh, "+<", $readfrom or die "READFROM2: open file $readfrom for the clause failed: $!\n";
            print "\n   READFROM2: file $readfrom opened for read...";
            $|=1;
            print "\n   READFROM2: reading data file ...\n";

            $clausevalue=join '',<$datafh>;         #join array into one string
            $clausevalue=~s/#.*\n/\n/g;         #remove commented part
            $clausevalue=~s/^\s*\n//mg;         #remove any pure blank lines

            return $clausevalue;
        }else{          #otherwise,
            print "\n   READFROM2: file $readfrom does not exist!\n";
            return undef;
        }

    }elsif ($readfrom=~/^\s*\.\s*$/){               #if readfrom .
        print "\n   READFROM2: readfrom configured as current config file(.)\n";
    }else{
        print "\n   READFROM2: illegal filename $readfrom!\n";
    }
}

################################################################################
################################################################################
################mylib.pm:  contains defined functions ##########################
################################################################################
################################################################################

sub login{  #this function checks the login params(param1) and trying to login remote box
        #it returns the telnet objects
                #
                #param1: a ref to an login params group
                #param2: debugmode
                #return: if login is valid, return $t, a Net::Telnet objects

    my $p_loginparams=shift;        #pass the 1st param, a ref to an login array
    my $p_options=shift;

    my $debugmode=$p_options->{debug};
        my $normal=$debugmode if ($debugmode=~/normal/ or $debugmode=~/1/);
        my $debug=$debugmode if ($debugmode=~/debug/ or $debugmode=~/2/);
        my $extensive=$debugmode if ($debugmode=~/extensive/ or $debugmode=~/3/);       
    
    my $logfile=$p_options->{checklog_file};
    my $telnet_buffer=$p_options->{telnet_buffer};
    my $init_prompt=$p_options->{init_prompt};
    my $telnet_timeout=$p_options->{telnet_timeout};
    
    
    my $telnet1=    $p_loginparams->[0];    #get the 1st level login1 
    my $login1= $p_loginparams->[1];    #
    my $password1=  $p_loginparams->[2];    #
    my $telnet2=    $p_loginparams->[3];    #get the 2nd level login
    my $login2= $p_loginparams->[4];    #
    my $password2=  $p_loginparams->[5];    #
    my $enable2=    $p_loginparams->[6];    #get the enable pw
        
    my $t = new Net::Telnet (       #telnet and login
            Timeout => $telnet_timeout,
            Input_log => "$logfile",
            Prompt => $init_prompt,

#           '/[\$%#>]\ ?$|login: $|password: $|username: $/i',          
#           Prompt => '/login: $|password: $|username: $/i'
            );
    
    print "\nLOGIN: create an initial input logs file (local timestamp only!): $logfile\n";

    $t->max_buffer_length($telnet_buffer);      #increase output buffer from 1M to around 4M
    
    if ($telnet1 and $login1 and $password1){       #if 1st level entry is valid
        print "LOGIN: connecting to $telnet1\.\.\.\n";
        $t->open($telnet1);             #then try login 
        $t->login($login1, $password1);         #if not succeed it will exit.
        print "LOGIN: conneted to $telnet1 via user:$login1 and password:$password1\n" if ($debug or $extensive);

        if ($telnet2 and $login2 and $password2){   #if there is valid 2nd level login
            print "LOGIN: connecting to $telnet2\.\.\.\n";
            $t->cmd("telnet $telnet2");     #then try login
            $t->cmd("$login2");
            #$t->cmd("$password2");  
            print "LOGIN: conneted to $telnet2 via user:$login2 and password:$password2\n"if ($debug or $extensive);
            
            if ($enable2){              #if there is enable pass
                print "LOGIN: enable 15 with enable password:$enable2\n";
                $t->cmd("enable");      #try it
                $t->cmd("$enable2");
            }else{
                print "LOGIN: no enable password\n";    #otherwise ignore it
            }
        }else{                      #if no 2nd level login then exit.
            print "LOGIN: no 2nd login hop\n"
        }
    }
    else{
        print "LOGIN: wrong login info!\n";
    }
    print "\nLOGIN: the returned telnet instance is:",Dumper($t) if ($extensive);
    $t;                         #return telnet object anyway.
}


sub stsplit{            #split (ref of��show-tech output into a (ref of)hash
                #$showveroutput=hash{show ver}
                #param1: a ref to an showtech output string
                #param2: a ref to a hash data: cmdsoutput
                #return: a ref to an hash: %$stsplit
    my $p_showtech=shift;
    my $p_cmdsoutput=shift;
    my $debugmode=shift;
    
    print "STSPLIT: show-tech file read:\n$$p_showtech\n" if $debugmode;
    
    my @cli_and_output=( $$p_showtech=~/\(tech-support\)\#\s    #'(tech-support)# '
                        (.*)            #capture:$1   'show chassis'
                        \n([\d\D]+?)\n      #capture:$2   anything
                        \[\d+\]\s       #'[10] '
                        (?=
                            (?:\(tech-support\)\#\s)  #'(tech-support)# '
                        )
                      /ixg );

    grep {$_=~s/^\s+|\s+$//g} @cli_and_output;
    
    %$p_cmdsoutput=@cli_and_output;
    
#   return $p_cmdsoutput;
}

sub getobjfromcli2{
                #param1:output string of a cli
                #param2:pattern string
                #param3:pattern string
                #return: an array of all matching parts
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
        #this function parse the data clause and get all 'wanted' data
        #it check what is wanted out of which cli
        #  if cli contains dynamic params
        #   use cmdsoutputs db to get the value and replace cli with a real one
        #   then telnet and update cmdsoutputs
        #  if cli has been executed(hence outputs already a/v), 
        #   use cmdsoutputs db to get wanted values and fill %data
        #  else
        #   telnet and execute it, then update cmdsoutputs
        #input-param1:telnet object $t, when necessary, telnet to box to get the cli-output
        #input-param2:ref to %cfgfopt, provide "wanted" lists and pattens
        #input-param3:ref to %cmdsoutputs,DB of (cli,outputs) pairs
        #output-param4:generate ref to %data (cli,wanted, value triples)
        #input-param5:debugmode
        
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
    my @cmds=@{$p_datatype->{commands}};    #get configured cmd lists in precheck/check/dotrue/dofalse statement
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
    
    while ( @cmds and !$interupted ) {          #for $cli in each precheck statement
    
        my $cli_ori=$cli=shift @cmds;   #get the cli and back it up
        my $p_cmds;

        print "\n    DATAPARSE: get one command:[$cli]\n" if $extensive;
        
        #######detect if it contains vars that needs substitutions, and do the job when needed
        if ($cli=~/@(\S+)/){    #if it contains a '@', then it's a indirect cli,like:
                    #   precheck    showiproute_iB={show ip route}:{...}
                    #   precheck    adjID={show ip route @showiproute_iB detail}{...}
                    #substitue value inside and generate a list of executable clies
                    #:@newclies
            print "\n        DATAPARSE: this looks an indirect command containing values to be replaced...\n" if $extensive;

            my $wanted=$1;              #get the dynamic param,like "showiproute_iB",which should
                                #be wanted part of some previous clis,which should be 
                                #existing in %data hash already
                                
            my $value=getvaluefromwanted($p_data,$wanted);  
                                #get the ref to the value array from %data
                                #this should be success.
                                #Note:
                                #  the 1st configured capture always need to be
                                #  direct cmd,so value of "wanted" in all later indirect 
                                #  capture will always be a/v already

            
            print "\n        DATAPARSE: the value of dparam [$wanted] is [@$value]\n" if $extensive;

            my @newclies;
            foreach (@$value){      #take each values in the array
                $cli=~s/@(\S+)/$_/; #replace the cli
                push @newclies,$cli;    #then push the new cli into an array    
            }               #now we get the array of new clies
            
            print "\n        DATAPARSE: composing the real cli list [@newclies]\n" if $extensive;
            $p_cmds=\@newclies;     #get the ref to this new cli list

        }else{                  #otherwise it's a direct cli
            print "\n        DATAPARSE: this looks a direct command...\n" if $extensive;
            $p_cmds=[$cli];         #get the ref to this cli list
        }
                            #so far we convert all CLIes into direct version and
                            #get the ref to the list of all direct cli(es) from capture
        

        #####handle the CLI list,get output from online or file depending on online mode settings
        if ($online){
            foreach (1..$times+1){      #run this CLI multiple times if $time was configured
                            #but only the last run will be recorded/analyzed
                            #check checklogfile for all trials
                cmds2cmdsoutputs($t,$cli_prompt,$p_cmds,$p_cmdsoutputs,$p_options,$p_difftime);
            }
        }   
        else{
            #if not exist, get it from file
            #   if fail, report info and ignore the cmd
            cmdslogfile2cmdsoutputs($cmdslogfile,$p_cmds,$p_cmdsoutputs,$debugmode);        
        }
        
        #####now parsing CLI outputs 
        #get all 'wanted' parts for this cli
        print "\n        DATAPARSE: use cmd [$cli_ori] in cfgfopt tree to get wanted and ptns\n" if $extensive;
        @wanted=keys %{$p_datatype->{$cli_ori}};    #get wanted list
#       print "\n            DATAPARSE: command is:",Dumper($p_datatype->{$cli_ori});
        print "\n            DATAPARSE: [cli]:[wanted] is: [$cli_ori] : [@wanted]\n" if $extensive;
        
        
        foreach (@wanted){          #with current cli, for each wanted,
                            #get the corresponding patterns 
            my $wanted=$_;
            ($ptn1,$ptn2)=@{$p_datatype->{$cli_ori}{$wanted}}[0,1]; 
            if ($extensive){
                print "\n                DATAPARSE: one [cli]:[wanted] is [$cli_ori]:[$_]\n";
                print "\n                DATAPARSE: using patten:[$ptn1][$ptn2]\n" if ($ptn1 and $ptn2);
                print "\n                DATAPARSE: using patten:[$ptn1][undef]\n" if ($ptn1 and not $ptn2);
                print "\n                DATAPARSE: no pattens\n" unless (defined $ptn1 or defined $ptn2)
            }
            
#           print "\nthe output of cli:[$cli] is $p_cmdsoutputs->{$cli}\n" if $extensive;
            #then use the patten to capture the values for all real clies out of %cmdsoutputs
            #and update data hash
            foreach (@$p_cmds){
                my $realcli=$_;
#               print "\n        using cli -->$realcli\n";
                my @wantedvalue=();
                my $cmdoutput;
                #get the value only if the cli output exists, 'if' here is mostly for off line mode,
                # to ensure we don't generate it by ref it (perl auto-vivi)
                $cmdoutput=$p_cmdsoutputs->{$realcli}{output} 
                    if (exists $p_cmdsoutputs->{$realcli}{output});
                
                if ($cmdoutput){
                    print "\nDATAPARSE: cli output exists..check the wanted values..\n" if ($debugmode);
                    
                    ############add some codes here to diff check and checkno
                    @wantedvalue=getobjfromcli2($cmdoutput,$ptn1,$ptn2,$debugmode);
                    if ($debugmode){
                        @wantedvalue?(print "\nDATAPARSE: the wanted values are:\n@wantedvalue\n\n"):(print "\n                DATAPARSE: get no wanted values\n\n");
                    }
                }else{
                    print "\nDATAPARSE: cli output doesn't exist!\n" if ($debugmode);
                }
                    
#               print "\nDATAPARSE: the wanted values are:@wantedvalue\n\n" if @wantedvalue;
                $p_data->{$realcli}{$wanted}=\@wantedvalue;
            }
        }
    } #end of while (@cmds)
    
    print "\n\nDATAPARSE: the cmdsoutputs structure looks:\n",Dumper($p_cmdsoutputs) if $extensive;
    print "\n\nDATAPARSE: the data structure looks:\n",Dumper($p_data) if $extensive;
}
    #   

sub cmds2cmdsoutputs{           #this fucntion use @cmds as input,use telnet object to login the box
                    #then it executes commands online and collect outputs
                    #and generate the %cmdsoutputs hash
                    #input param1:telnet object
                    #input param2:ref to @cmds
                    #output param3:ref to @cmds2outputs
                    #input param3:debugmode
                    #return: an array composed of all cli outputs
    my $t=shift;
    my $cli_prompt=shift;
    my $p_cmds=shift;
    my $p_cmdsoutputs=shift;
    my $p_options=shift;
    my $p_difftime=shift;
    
    
    my $rtimetype=$p_difftime->[0]; #remote time type: gm
    my $dseconds=$p_difftime->[1];  #time diff in seconds
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
        if( $$p_cmdsoutputs{$_} and (not $repeatmode)){ #if already in hash and not repeatmode
            print "\n            CMDS2CMDSOUTPUTS: the command output is already in hash,no need to update\n" if defined $extensive;
            
        }else{                      #otherwise get it online and update the hash
            print "            CMDS2CMDSOUTPUTS: the command output is not present or repeatmode is set,get the output now...\n" if defined $extensive ;
            $cmdoutput=join '',$t->cmd(String => "$_",,Prompt=>$cli_prompt) ;
            print "\n            CMDS2CMDSOUTPUTS: the new output is:\n[\n",$cmdoutput,"\n]\n" if defined $extensive;
            print "            CMDS2CMDSOUTPUTS: put into cmdsoutputs DB...\n" if defined $extensive;
            $$p_cmdsoutputs{$_}{output}=$cmdoutput; #write cmdsoutputs  
            #write timestamp, depending on timing setup (local/remote mode),use local/remote time
            #also under remote time we need to know it's GMT or not
            $$p_cmdsoutputs{$_}{localtime}=lr_time($timing,$p_difftime);
        }
    }
    
    print "\n        CMDS2CMDSOUTPUTS: cmds2cmdsoutputs checking&updating done...\n\n" if defined $extensive;
    return values %$p_cmdsoutputs;
}


sub cmdslogfile2cmdsoutputs{
                    #this function parse cmdslog file and generate %cmdsoutputs hash
                    #input:cmdslog filename
                    #output:%cmdsoutputs hash
                    #param1:cmdslog filename
                    #param2:ref to %cmdsoutputs
                    #param3:debugmode
    my $cmdslogfile=shift;
    my $p_cmds=shift;
    my $p_cmdsoutputs=shift;
    my $debugmode=shift;
        my $normal=$debugmode if ($debugmode=~/normal/ or $debugmode=~/1/);
        my $debug=$debugmode if ($debugmode=~/debug/ or $debugmode=~/2/);
        my $extensive=$debugmode if ($debugmode=~/extensive/ or $debugmode=~/3/);
    print "\n        CMDSLOGFILE2CMDSOUTPUTS: prepare to update cmds2cmdsoutputs from cmdslogfile...\n" if ($debug or $extensive);


#   print "\nsplit $cmdslogfname output into cmdsoutputs hash !...\n" if ($debug or $extensive);
#   stsplit(\$logfile,$p_cmdsoutputs);  #build cmdsoutputs hash from show tech
    my $cli_prompt;

    foreach (@$p_cmds){
        my $cli_ori=my $cli=$_;
        
        if ($cli=~s/( )/\\$1/g){
            print "\n            CMDSLOGFILE2CMDSOUTPUTS: change cli for matching:[$cli]\n" if ($debug or $extensive);
        }
        
        #parsing the cmdslogfile(can be show-tech),there is 2 possible prompts:
        #   [local]tac-se1200-1#show ip int b
        #   [950] (tech-support)# show ...  
        if($cmdslogfile=~/\n            #if cmd can be found in log file: get the outputs
        
                    (?:\[\d+\]\ )?  #   (for show-tech file,ignore: ..[nnn] ..)
                    (\S.*?)     #a prompt--any strings before the cli
                            #can be ..[local]tac-se1200-1#..or..(tech-support)# ..
                    $cli        #cli
                    [\f\t\r ]*  #may followed by any white spaces
                    \n      #a new line seperate command and output
                    \s*?        #ignore preceding white spaces
                       (\S[\d\D]*?) #anything afterwards and before the prompt
                    \s*?        #ignore trailing white spaces
                    (?:\[\d+\]\ )?  #   (for show-tech file,ignore: ..[nnn] ..)
                    (?:\1       #the same prompt as 1st one: 
#                       |   #  or
#                   .*$     #an ending line
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
          }else{                    #otherwise do nothing
              #still generate hash keys, just fill in undef
              $p_cmdsoutputs->{$cli_ori}{'output'}=undef;
              $p_cmdsoutputs->{$cli_ori}{'localtime'}=(localtime)." (make no sense under offlinemode)";
              print "\n            CMDSLOGFILE2CMDSOUTPUTS: not found cmd [$cli] in cmdslogfile!\n";
              print "\n            CMDSLOGFILE2CMDSOUTPUTS: ignore this cmd in capture statement!\n";
          }  
    }
    print "\n        CMDSLOGFILE2CMDSOUTPUTS: cmds2cmdsoutputs checking&updating done...\n" if ($debug or $extensive);
}


#($p_data,$wanted)
sub getvaluefromwanted {
                    #input $p_data
                    #input $wanted
                    #return $value
#$VAR1 = {
#          'show radius statistics' => {
#                                        'reqsend' => ['140'],
#                                        'reqsendfail' => ['0]'
#                                      },
#          'show ip route' => {
#                               'showiproute_iB' => ['0.0.0.0/0]'
#                             },
#          'show ip route $showiproute_iB detail' => {},
#
#          'show hardware detail' => {
#                                      'slot7sn' => [''],
#                                      'slot8sn' => [' 6Y71B370824621   ']
#                                    },
#          'show crashfiles' => {
#                                 'crashfiles' => ['']
#                               }
#       };

    my $p_data=shift;
    my $wanted=shift;
    my $cli;
    foreach (keys %$p_data){        #for each command
        $cli=$_;
        last if grep $_ eq $wanted,keys %{$p_data->{$cli}}; 
                        #from the {wanted,valuearray} hash,search the wanted list
                        
    }
    my $value = $p_data->{$cli}{$wanted};   #return ref to the valuearray
}

sub actionparse{            #this function do followings:
                    #1) replace the checkstate/comp/final to perl executable
                    #2) 

    ################################################
    my $p_data=shift;
    my $datatype=shift;
    my $debugmode=shift;
        my $normal=$debugmode if ($debugmode=~/normal/ or $debugmode=~/1/);
        my $verbose=$debugmode if ($debugmode=~/verbose/ or $debugmode=~/2/);
        my $extensive=$debugmode if ($debugmode=~/extensive/ or $debugmode=~/3/);       
    
    print "\nACTIONPARSE: calculating actions...\n";
    
    #######1. generate declaration for wanted value: array, scalar,scalar_all,scalar_setflag,print test code
    #   
    #
    my $dec_array='';
    my $dec_scalar='';
    my $dec_scalar_all='';
    my $print_test='';
    my $checkdata='';
    foreach my $cli (keys %$p_data){            #take a cli in data hash
        foreach (keys %{$p_data->{"$cli"}}){        #for every wanted part from the output
                                #generate perl declaration
            print "ACTIONPARSE: \n    got a \$wanted :[$_]\n" if $extensive;
            
            #1) generate perl declarations
            $dec_array .="    my \@$_=\@{\$$datatype"."{\'$cli\'}{\'$_\'}};\n";
    #       $dec_array .="    my \@$_=\@{\$$datatype"."{\'$cli\'}{\'$_\'}} if (\$$datatype"."{\'$cli\'}{\'$_\'});\n";
            
            $dec_scalar .="    my \$$_=\$$_"."[0];\n";
            $dec_scalar_all .="    my \$$_"."_all=join '', \@$_;\n";
            #debugging print codes
            $print_test.="    print \"    test:the wanted array [$_] looks:\@$_\\n\";\n" if $extensive;

            #2) glue all data into a $checkdata scalar
            my @value=@{$p_data->{"$cli"}{"$_"}};
            $checkdata.=join '',@{$p_data->{"$cli"}{"$_"}};
            print "ACTIONPARSE: array value now is:@value\n" if ($verbose or $extensive);
        #   print "ACTIONPARSE: \$checkdata now is:$checkdata\n" if ($verbose or $extensive);

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
    #3) compare value arrays and generate scalar assignment statement accordingly
    #if it's values are all same, set the wanted var to 0 ;
    foreach my $cli (keys %$p_curdata){         #take a cli in data hash
        foreach (keys %{$p_curdata->{"$cli"}}){     #for every wanted part from the output
            
            my $p_curvalue=$p_curdata->{"$cli"}{"$_"};      #take current value(array ref)
            my $p_oldvalue=$p_olddata->{"$cli"}{"$_"};      #take a prev. value(array ref)
        
            if ($comp->compare($p_curvalue, $p_oldvalue)) { #and compare, same
                print "DATACOMPARE: value of ($_) are the same:\n@$p_oldvalue\n-------------\n@$p_curvalue\n" if ($debug>=2);
                $scalar_setflag.="my \$$_=0;\n";    #set the scalar to 0,t.b.eval
                print "DATACOMPARE: set $_ = 0\n=============\n" if ($debug>=2);
            #otherwise, set the wanted var to 0 ;
            }else{                  
                print "DATACOMPARE: value of ($_) are not same:\n@$p_oldvalue\n-------------\n@$p_curvalue\n" if ($debug>=2);
                $scalar_setflag.="my \$$_=1;\n";    #set the scalar to 0,t.b.eval
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
    
    if($checkchange){       #if checkchange configured,eval it

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

        $truefalse=$checkchange_res;        #will be prevailed by checkchange
        print "\nRULECALC: \$checkchange_res after eval is: $checkchange_res\n\n" if ($debug>=2);
    }

    if($checkstate){        #if checkstate configured,eval it

#       my $checkstate_print="print \"checkstate result is now:\$checkstate_res\\n\";";

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
        $truefalse=$checkstate_res;     #will prevail checkchange
        print "\nRULECALC: \$checkstate_res after eval is: $checkstate_res\n\n" if ($debug>=2);

    }

    if($checkfinal){    #if checkfinal configured,eval it

#       my $checkfinal_print="print \"checkfinal result is now:\$checkfinal_res\\n\";";

        my $checkfinal_final=
                "\$checkfinal_res=".    
                $checkfinal.
                ";\n"
                ;

        print "\nRULECALC: \$checkfinal_final to be evaled are:\n[\n$checkfinal_final\n]\n" if ($debug>=2);
        print "RULECALC: now eval checkfinal_final...\n";

        eval $checkfinal_final;         
        print $@ if ($@);
        $truefalse=$checkfinal_res;     #will prevail checkchange
        print "\nRULECALC: \$checkfinal_res after eval is: $checkfinal_res\n\n" if ($debug>=2);

    }

    unless ($checkstate or $checkchange or $checkfinal){    #if none of them configured
        $truefalse=($checkdata)?(1):(0);        #do OR (backward compatible)

        print "\$truefalse by default is: $truefalse\n\n" if ($debug>=2);

    }
    return $truefalse;
}

sub cmdsoutputs_format{
    my $p_cmdsoutputs=shift;    #input: cmdsoutputs structure
    my $p_res=shift;        #output:an array of cli lists, formatted cmdsoutputs, original cmdsoutputs
    
    my $i;
    my $cmds='';
    my $cmdsoutputs_ori='';
    my $cmdsoutputs='';
    
    foreach (keys %$p_cmdsoutputs){
        ++$i;
        $cmds.="$_\n";
        
        my $cli_fmt="$i)    $_  (at $p_cmdsoutputs->{$_}{localtime})";
        
        if ($p_cmdsoutputs->{$_}{output}){              #if there are outputs
            $cmdsoutputs_ori.=$p_cmdsoutputs->{$_}{output};         
            $cmdsoutputs.=
                "$cli_fmt"                              #cli
                ."\n"
                .'-' x (length $cli_fmt)                  #------------
                ."\n"
                .$p_cmdsoutputs->{$_}{output}           #outputs
                ."\n\n\n"
                ;
        }else{                                          #if no outputs
            $cmdsoutputs.=
                "$cli_fmt"  #cli
                ."\n"
                .'-' x (length $cli_fmt)
                ."\n"
                ."(no outputs)"                         #say "no outputs"
                ."\n\n\n"
                ;           
        }
    }
    @$p_res=($cmds,$cmdsoutputs,$cmdsoutputs_ori);
}

sub sendemail{      #sendemail
            #param: subjects
            #param: msgs
            #param: ref to a list of files to be attached
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
#              auth =>  'login',
#              authid =>    'routermonitor@sina.com',
#              authpwd =>   'routermonitor',
              })
              )
          and print "\nSENDEMAIL: email sent successfully.\n"
         )
         or die "$Mail::Sender::Error\n";       
    };
    print "can't send email!\n[\n$@\n]\n" if ($@);
}

sub addtime{
    #this function attach a current(not necessarily local) timestamp to the string, 
    #the time will be based on timing option: local/remote
    #it then depending on the 'force' param,
    #it either not to force (only substitute when there is a %t),
    #   or forces the attachment (attach even if no %t) of the timestamp
    #
    
    my $string=shift;       #the string to attach the time to
    my $force=shift;        #seek for %t or not
    my $timing=shift;       #use local or remote machine time
    my $p_difftime=shift;       #time difference
    
    my $time;
    
    #use lr_time if timing was given, otherwise use localtime
    $time=(defined $timing)?lr_time($timing,$p_difftime):localtime;
    
    $time=~s/^|\s+|:/_/g;       #convert all blank to _
    
    if ($force){            #if forced      
        ($string=~/%t/)?($string=~s/%t/$time/): #if it contains %t then substitue
        $string=~s/(.*)\.\w+$/$1$time/;     #otherwise also inseat the timestampt
    }else{              #if not forced(or not given)
        $string=~s/%t/$time/;   #seek for %t and replace only when found
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
    print "\nPROMPT: detecting a proper prompt for later commands...\n";    #start detecting prompt
#   $t->cmd("\n");
    my @pwd=$t->cmd("\n");
    print "PROMPT: the current working dir:\n[\n@pwd\n]\n" if ($debug);
    my $prompt_ori=$cli_prompt=$pwd[1];  #[local]tac-se800-2
    $cli_prompt=~s#\@#\\\@#;
    $cli_prompt=~s#\[#\\\[#;        #\[local]tac-se800-2
    $cli_prompt=~s#\]#\\\]#;        #\[local\]tac-se800-2
    $cli_prompt=~s#^#/#;        #/\[local\]tac-se800-2
    $cli_prompt=~s#$#/#;        #/\[local\]tac-se800-2/
    print "\nPROMPT: A prompt{$prompt_ori}detected\n" if ($debug);
    return $cli_prompt;
}

sub time_diff{
    my $localtime=shift;
    my $remotetime=shift;
    
    my $lseconds=parsedate("$localtime");
    my $rseconds=parsedate("$remotetime");
    my $timetype=($remotetime=~/gmt/i)?'gm':'local';
    my $diffseconds=$rseconds-$lseconds;    #difference in absolute seconds
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
    my $p_options=shift;            #options
    my $p_difftime=shift;           #time difference
    
    my $size2zip=$p_options->{size2zip};    #get size2zip and timing
    my $timing=$p_options->{timing};
    my $host=$p_options->{host};
    
                        #get current file name
    my $checklog_file=$p_options->{checklog_file};
    my $checkonhit_file=$p_options->{checkonhit_file};  

                        #get the base file names
    #my $checklog_file_ori      =   $p_options->{checklog_file_ori};
    #my $checkonhit_file_ori    =   $p_options->{checkonhit_file_ori};
    
    #generate mapping bet. current file name and the name base
    $p_options->{$checklog_file}        =   $p_options->{checklog_file_ori};
    $p_options->{$checkonhit_file}  =   $p_options->{checkonhit_file_ori};
    
    foreach my $file2zip (  $checklog_file, $checkonhit_file ) {        #for each current file  
        print "ZIPBIGFILE: \nfile to be checked is $file2zip\n";
        my $filesize=-s $file2zip;              #get the file size

        if ($filesize > $size2zip){             #if it is too big
            print "\nZIPBIGFILE: size of log file $file2zip ($filesize) exceeds the max. limitation($size2zip), need to be zipped...\n";        
            print "\nZIPBIGFILE: file base is $p_options->{$file2zip}\n";
            #generate a new file name with new timestamps (based on the name base and timing setup)
            my $file2zip_new=parsename( $p_options->{$file2zip},
                                                                    $host,
                                                                    1,
                                                                    $timing,
                                                                    $p_difftime);
            print "\nZIPBIGFILE: prepared a new file name $file2zip_new...\n";
            
            
            copy($file2zip,$file2zip_new);          #copy logs to a new txt file
            print "\nZIPBIGFILE: copied logs from $file2zip to $file2zip_new...\n";
            
            my $zip=Archive::Zip->new();                #generate a new zip obj
            my $file_member=$zip->addFile( "$file2zip_new");    #zip it 
            
            my $file2zip_new_zip=$file2zip_new;
            $file2zip_new_zip=~s/(.txt)$/.zip/;         #
            unless ( $zip->writeToFileNamed("$file2zip_new_zip")==AZ_OK ){ 
                 die 'write error when zipping';            #and save the zip
            }
            print "\nZIPBIGFILE: saved as a new zip file: $file2zip_new_zip\n";     
            
            unlink "$file2zip_new";                 #then delete txt file
            
            `echo > $file2zip`;                 #empty the original log file
            $filesize=-s $file2zip;                 #check new size
            print "\nZIPBIGFILE: empty original log file $file2zip(now size is $filesize)...\n";

        #   open my $temp, '>', $file2zip;              #empty the file
        #   unlink "$file2zip";                 #then rm old file
        }else{
            print "\nZIPBIGFILE: size of log file $file2zip ($filesize) is still within the max. limitation($size2zip), no need to be zipped for now...\n"; 
        }
    }
}


sub get_commands{
    return {
        
        ####################system commands######################
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
                
        ###### shortcuts using system call, not windows compatible######
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
        ###### shortcuts using system call, not windows compatible######
        
                        
        debug_complete => { desc => "Turn on completion debugging",
            minargs => 1, maxargs => 1, 
            args => "0=off 1=some, 2=more, 3=tons",
            proc => sub { $term->{debug_complete} = $_[0] },
        },      
        

        ####################remote check commands######################

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
        
        
        ####################remote check parameters######################       
        
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
                        #this function do most options handling in the order of priorities
                        
    ############option handling: from default: pri4
    #default values for all options: pri0
    my $options=shift;
    my $options_cli=shift;
    my $options_def=shift;
    my $cfgfopt=shift;
            
    %$options=%$options_def;                            #start from default options

    ############option handling: from CLI: pri1
    ##important to keep in mind that, all options here, are already created and existing!
    ##but there is no value (not defined) until seen in command options!!
    my $getopt = GetOptions (       
            "shell"     =>  \$options_cli->{shell},     #set shell to 1, def 0
            "history_shell" => \$options_cli->{history_shell},
            
            "usage"     =>  \$options_cli->{usage},     #display version
            
            "online!"   =>  \$options_cli->{online},    #-online: set online to 1, def 0
            "offline"   =>  sub {                       #force 1 rounds and no sleep under offline mode
                            $options_cli->{online}=0;
                            $options_cli->{rounds}=1;
                            $options_cli->{sleep}=0;
                        },                              #-offile or -noonline: set online to 0
            "repeat!"   =>  \$options_cli->{repeat},    #-norepeat: set repeat to 1,def 0
            "times=i"   =>  \$options_cli->{times},     #repeat a cmd for times
            "rounds=i"  =>  \$options_cli->{rounds},    #-rounds x: def 3
            "sleep=i"   =>  \$options_cli->{sleep},     #-sleep x:def 10
                                                        
                                                        #-nosleep=sleep 0
            "nosleep"   =>  sub {$options_cli->{sleep}=0},
            "debug=i"   =>  \$options_cli->{debug},     #-deb 0/1/2/3,def 0
                                                        #-nodebug, goback to normal
            "nodebug|quiet" =>  sub {$options_cli->{debug}=0},  
                                                        #-nochecklog, turn off telnet checklog
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
            "config_file|cfg=s" =>  \$options_cli->{config_file},   #
            "log_dir|logdir=s"  =>  \$options_cli->{log_dir},    
            "checklog_file|checklog=s" =>   \$options_cli->{checklog_file},
            "checkonhit_file|hit=s" =>  \$options_cli->{checkonhit_file},
            "cmdlog_file|cmdlog=s" =>   \$options_cli->{cmdlog_file},

            "sendemail!"    =>  \$options_cli->{sendemail}, #-sendemail: set sendemail to 1, def nosend
            "smtpserver=s"  =>  \$options_cli->{smtpserver},
            "emailfrom=s"   =>  \$options_cli->{emailfrom},
            "emailfakefrom=s" =>    \$options_cli->{emailfakefrom},
            "emailto=s" =>  \$options_cli->{emailto},
            "emailreplyto=s" => \$options_cli->{emailreplyto},
            "emailsubj=s"   =>  \$options_cli->{emailsubj},
            "emailpref=s"   =>  \$options_cli->{emailpref}, #foreword in email text
            "emailmax=i"    =>  \$options_cli->{emailmax},

            "help|?"    =>  \$options_cli->{help},      #-help or -?, set help to 1
            );


    #conver value of all CLI options to lower case (making them case insensitive)
    grep {$options_cli->{$_}=~s/(.*)/\L$1/ if (defined $options_cli->{$_})} (keys %$options_cli); 

    ############pre-handling help setting from CLI: pri1
    if (!$getopt or                                     #when getopt fail
        $options_cli->{help}                            #or '-help' is given
        ){
        print "\nhelp information!\n";                  #print detail usage info
        die USAGEMSG;
    };
    
    if ($options_cli->{usage}){                         #if '-usage'
        die USAGEMSG2;                                  #print brief usage
    }
    
    ############print options from default: pri4
    $options->{debug}=$options_cli->{debug}             #restore back debug mode 
        if (defined $options_cli->{debug});             #if set in CLI
    print "CHECKOPTIONS4CLI: options from defaults are:\n",Dumper($options) if ($options->{debug}==3);


    #load options from env.: priority 3                 #check ENV settings for each of options we cared of
    eval {$options->{$_}=$ENV{$_} 
        if (defined $ENV{$_})} foreach (keys %options);
    eval {$options->{$_}=$ENV{$_} 
        if (defined $ENV{$_})} foreach (keys %options_cli);

    if(
        (   not (defined $options_cli->{shell})         #if not under shell
            and                                         #then: following is wrong
        (
            (                                           #lack of host
            not (defined $options_cli->{host})
            )
            or                                          #or
            (                                           #1) under online mode
                ($options_cli->{online})                #   but lack of host
                and
                not (defined $options_cli->{host})  
            )   
        )
        
        )
      ){                                                
                                                        #print brief usage
        print "\nCHECKOPTIONS4CLI: wrong parameter combinations!\n";
        print "\nCHECKOPTIONS4CLI:  1) host is a MUST unless under shell mode!\n";
        die USAGEMSG2;      
    }

    $options->{debug}=$options_cli->{debug}             #restore back debug mode 
        if (defined $options_cli->{debug});             #if set in CLI
        
    print "CHECKOPTIONS4CLI:: options after env. are:\n",           
        Dumper($options) if ($options->{debug}==3);

    print "\nCHECKOPTIONS4CLI:########analyzing configuration file#############\n\n" 
        if ($options->{debug});
    $options->{config_file} = $options_cli->{config_file} 
        if ( defined $options_cli->{config_file} ); 
        
    cfgfparse(  $options->{config_file}, 
                $cfgfopt,$options->{debug} 
                );                                      #config file parsing stageI

    ############get and print options from the config file: pri2
    foreach (keys %options){                            #update every existing entry in %options
        eval {
            if (exists $cfgfopt->{globalsettings}){     #make sure don't generate new key "globalsettings"
                if (exists $cfgfopt->{globalsettings}{hash}){   #make sure don't gen. new key "hash"
                    $options->{$_}=$cfgfopt->{globalsettings}{hash}{$_} 
                        if (defined $cfgfopt->{globalsettings}{hash}{$_});
                }
            }
        }
    }

    if (exists $cfgfopt->{globalsettings}){             #update %option with every entry in %options_cli
                                                        #make sure don't generate new keys "globalsettings" 
                                                        #if they don't exist
        if (exists $cfgfopt->{globalsettings}{hash}){   #make sure don't gen. new key "hash"
            eval {  $options->{$_}  =   $cfgfopt->{globalsettings}{hash}{$_} 
                    if (    $cfgfopt->{globalsettings}{hash}{$_}    )
                 }
                foreach (keys %{$cfgfopt->{globalsettings}{hash}});
        }
    }   


    $options->{debug}=$options_cli->{debug}             #restore back debug mode 
        if (defined $options_cli->{debug});             #if set in CLI
        
    print "CHECKOPTIONS4CLI:: options after config file are:\n",
        Dumper($options) if ($options->{debug}==3);

    ############get and print options from CLI: pri1 (overide all)

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

    die USAGEMSG2 if (                                  #more conditions to exit can be added here...
                                                        #e.g.:
                not $options->{shell}                   #not shell mode...
                and                                     #but
                (                                       #online set and no host
                $options->{online} 
                and 
                not (defined $options->{host})  
                )   
                                                        #or, other conditions
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
        stat($file) or die "No $file: $!\n";    # die only stops this command
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
    
    
    ##generate dynamic code based on prechecking data
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
    eval $action if $action=~/\w+/;         #action execution
    if ($@){                    #if the eval run into error, provide some hints
        print "\nAUDIT: Error:\n[\n$@\n]\n";
        print "\nAUDIT: there are syntax error in your config action definition!\n";
        print "\nAUDIT: most probably the perlhandle clause contains progma/syntax, or the var name used in action clause is different than those defined in data clause!\n";
    }
}   

sub time_diff_print{
    ####these are only for printing
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
    
    #the email message will contains:
    #    what has been checked before/after the issue
    my ($msgs_check,$msgs_dotrue,$msgs)=();

    $msgs_check=$p_options->{emailpref} #email headwords 
        .$checkcmdsoutputs_pref     #and 
        .$checkcmds;            #commands set performed before the issue

    if ($fault_len > 2*$p_options->{emailmax}){ #if email is too long,brief a bit
        $msgs_check.=
            substr($checkcmdsoutputs,0,$p_options->{emailmax})  #excerpt the heading lines
            ."\n................snipped.................\n"
            .substr($checkcmdsoutputs,-$p_options->{emailmax})  #and tailing lines
            ;
    }else{                      #if not long,print all in email text
        $msgs_check.=$checkcmdsoutputs;
    }

    if ($dotruecmdsoutputs_ori){    #if further check found sth,print cmds in email     
        $msgs_dotrue=$dotruecmdsoutputs_pref
            .$dotruecmds
            ."\n\n\n\nthanks\nregards\nfrom remotecheck script"
            ;
    }else{              #otherwise ...
        $msgs_dotrue="but nothing were found on further check!"
            ."\n\n\n\nthanks\nregards\nfrom remotecheck script"
            ;
    }   

    $msgs=$msgs_check.$msgs_dotrue;

    my @files=();
    push @files,($p_options->{checkonhit_file},$p_options->{checklog_file});
    ####send email################################

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

sub prehandle{  #this function do some pre-handling:
        #    create dir for logs
        #    online mode: tag checklog_file name (w/ time or hostname)
        #       login handling
        #   timing handling (remote/local)
        #   prompt handling
        #    offline mode:
        #   simply open a checklog_file
        #return:
        #    fh of checkonhit_file (online mode)
        #    fh of checklog_file (offline mode)
        #new entries:
        #    $p_options->{checklog_fh_offline}
        #    $p_options->{checkonhit_fh_online}
        #    $p_options->{telnet_obj}
        #    $p_options->{checklog_file_ori}
        #    $p_options->{checkonhit_ori}
        #
    
    my $p_options=shift;
    my $p_cfgfopt=shift;
    my $p_difftime=shift;

    my $t=undef;

    my $host=$p_options->{host};                    #host need to check

    print "\n\nPREHANDLE:#############preparing dir and files for logs and reports####################\n\n";
    
    #backup dir base backup log file name base
    $p_options->{log_dir_ori}           =   $p_options->{log_dir};
    $p_options->{checklog_file_ori}     =   $p_options->{checklog_file}; 
    $p_options->{checkonhit_file_ori}   =   $p_options->{checkonhit_file};
    print "Prehandle: backed up log_dir name base: $p_options->{log_dir_ori}\n";        
    print "PREHANDLE: backed up checklog_file name base: $p_options->{checklog_file_ori}\n";
    print "PREHANDLE: backed up checklog_file name base: $p_options->{checkonhit_file_ori}\n";  

    #generate a dir name based on host and current (and unfortunately,local) time
    $p_options->{log_dir}=parsename(    $p_options->{log_dir_ori},
                                                                        $host );        
    
    #create a dir if it does not exist yet
    if ( -e $p_options->{log_dir} ){
        print "PREHANDLE: Dir $p_options->{log_dir} exists...";
    }else{  #if dir doesn't exist, create it
        mkdir( $p_options->{log_dir},07777 ) or die "can't make dir $p_options->{log_dir}!" ;
        print "PREHANDLE: Created a dir $p_options->{log_dir}...\n";
    }

    chdir( $p_options->{log_dir} );                 #change to that dir
    print "PREHANDLE: Enter dir $p_options->{log_dir}...\n";
    
    #generate an initial(localtime tagged) file name for checklog then update options
    $p_options->{checklog_file}=parsename($p_options->{checklog_file_ori},$host);
    print "PREHANDLE: get a file name for checklog_file base: $p_options->{checkonhit_file_ori}\n";
    
    if ($p_options->{online}){                      #online mode,
        print "\nPREHANDLE: online set,login ...\n";        
                                                    
        if (exists                                  #proceed only if $host was configured in cfg file
                $p_cfgfopt->{logininfo}{hash}{"$host"}
            ){          
                                                    #login and use a file to log telnet actions
            $t=login(   $p_cfgfopt->{logininfo}{hash}{"$host"},
                                $p_options  );
            $p_options->{telnet_obj}    =   $t;     #save the telnet obj
            
        }else{                                      #otherwise exit
            die "\nPREHANDLE: there is no information configured for $host under logininfo clause inside config file $p_options->{config_file}!\nplease double check!\n";       
        }
        
        $t->cmd("term len 0");                      #get all output without pause               
    
        ####get remote and local clock time:
    
        if ($p_options->{timing}=~/remote/){
            my $localtime=localtime;                #record local time
                                                    #record remote time 
            my ($remotetime)=$t->cmd("$p_options->{clock_cmd}");        
            print "\nPREHANDLE: time calculation..." if ($p_options->{debug});
            print "\nPREHANDLE: localtime now is:$localtime\n", if ($p_options->{debug});
            print "\nPREHANDLE: remotetime now is:$remotetime\n", if ($p_options->{debug});
                                                    
                                                    #calc time difference
            @$p_difftime=time_diff($localtime,$remotetime);     
                                                    #print the time difference
            time_diff_print($p_difftime,$p_options->{debug});   

            ####get the time different in seconds
            #   localtime       Wed May 27 14:46:58 2009
            #   remotetime      Wed May 27 06:44:56 2009 GMT            
            #   ($timetype,$diffseconds,$weeks,$days,$hours,$minutes,$seconds)
            #       0   1   2   3   4   5   6        
        }
        
        #update checklog file name: use local or remote time according to timing setup
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
        #override the checklog with the new name
        print "\nPREHANDLE: use new checklog file name $p_options->{checklog_file} for current session\n";
        $p_options->{checklog_file_fh}=$t->input_log($p_options->{checklog_file});


        #prepare a file name for checkonhit
        $p_options->{checkonhit_file}=parsename($p_options->{checkonhit_file_ori},
                                                $host,
                                                0,
                                                $p_options->{timing},$p_difftime);
        print "\nPREHANDLE: prepared a checkonhit file: $p_options->{checkonhit_file}\n";
        open my $checkonhit_fh, '>>', $p_options->{checkonhit_file}     
            or die "\nRUN: Could not open $p_options->{checkonhit_file}";
        $|=1;
        $p_options->{checkonhit_fh_online}=$checkonhit_fh;
        
    #   open my $scalar_fh, '>>', \$checkonhit;     #and also open a scalar
    #   $|=1;                       #write to file&scalar at same time
    #   my $tee_fh=IO::Tee->new( $checkonhit_fh, $scalar_fh );      

    
        #use a simple cli to detect cli_prompt
        if (!$p_options->{cli_prompt}){
            $p_options->{cli_prompt}=cli_prompt($t,
                                       'pwd',
                                       $p_options->{debug});
        }
        return $checkonhit_fh;              #return checkonhit fh under online mode
        
    }else{
        print "\nPREHANDLE: online not set,will parse cmd log file: $p_options->{cmdlog_file}\n";
    
        print "PREHANDLE: creating checklog file(output): $p_options->{checklog_file}\n";
        open my $checklog_fh_offline, '>>', $p_options->{checklog_file} #open the file
        or die "PREHANDLE: Could not open $p_options->{checklog_file}";
        $p_options->{checklog_fh_offline}=$checklog_fh_offline;
        return $checklog_fh_offline;        #return a checklog fh under offline mode
    }
}
sub log4offline{
        #generate a log file for offline mode (just to be compatible with online mode)
    my $checklog_fh=shift;
    my $p_check_res=shift;
    my $p_dotrue_res=shift;
    my $p_dofalse_res=shift;

    
    my $checkcmdsoutputs=($p_check_res->[1])?($p_check_res->[1]):('');
    my $dotruecmdsoutputs=($p_dotrue_res->[1])?($p_dotrue_res->[1]):('');
    my $dofalsecmdsoutputs=($p_dofalse_res->[1])?($p_dofalse_res->[1]):('');

#   my $checklog_offline='';
    my $checklog_offline=$checkcmdsoutputs.$dotruecmdsoutputs.$dofalsecmdsoutputs;

    print $checklog_fh $checklog_offline;
}

sub checkoptions4run{
            #check whether options are ready for run
            #return:
            #   1 if all options pass the examination for run
            #       1) host is existing and 
            #       2) found an clause matching with the host
            #   0 if any one failed
            #new option entry: hostdataclause
    my $p_options=shift;
    my $p_cfgfopt=shift;
#   my $p_options_run=shift;
    
    my $host=$p_options->{host};
    $p_options->{hostdataclause}='';            #name of the clause containing data
    
    if($host){                                      #if defined host
        foreach my $clausename (keys %$p_cfgfopt){  #grep the data clause based on host option
            if (
                ($clausename=~/data\s*$host/)       #if a clause contains an exact match
                or                                  #   or
                ($clausename=~/data\s*all\s*$/i)    #it contains wildcast match(keyword 'all')
                or                                  #   or
                ($clausename=~/data\s*$/i)          #it contains no host info
               ){                                   #that the clause we are seeking
                                                    
                $p_options->{hostdataclause} = $clausename;
            }
        }
        
        if($p_options->{hostdataclause}){       #thumbs up if found a match
            return 1;                               #
        }else{                                      #otherwise thumbs down
            
            print "\nCHECKOPTIONS: there is no information configured for $host under any data clause inside config file $p_options->{config_file}!\n";
            print "CHECKOPTIONS: please double check your config_file!\n";
            return 0;
        }
        
        
    }else{                                          #if no defined host then thumbs down
        print "CHECKOPTIONS4RUN:no host has been defined,please specifiy one\n\n";
        return 0;
    }
}

sub lr_time{        #calculate and return local/remote time based on 2 input:
            #  current localtime: localtime
            #  time discrepancy between local/remote: dsecond
    my $timing=shift;
    my $p_difftime=shift;
    
    my $rtimetype=$p_difftime->[0]; #remote time type: gm
    my $dseconds=$p_difftime->[1];  #time diff in seconds
        
    return
    ($timing=~/local/)?localtime:
    ($rtimetype eq 'local')?(localtime(timelocal(localtime)+$dseconds)):
    (gmtime(timegm(gmtime)+$dseconds)." GMT");
}

sub parsename{
        #this function will attach hostname and a timestampt 
        #to the original string (file name)
        #
    my $name_ori=shift; #original string
    my $host=shift;     #host name to attach

    my $force=shift;    #optional, force (only substitute when %t found) or not 
    my $timing=shift;   #optional, local/remote
    my $p_difftime=shift;   #optional, time difference under remote mode
    
    
    return ($timing)?(addtime   #if timing is given,use 4 params version of addtime
                ( addhost($name_ori,$host),
                $force,
                $timing,
                $p_difftime)
             ):
            (addtime    #otherwise (localtime) use 1 params version (attach localtime)
                ( addhost($name_ori,$host)
                )
            );
}   
