package Cpanel::RoR;

# cpanel - Cpanel/RoR.pm                           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::SafeRun::Errors ();

use Cpanel                                ();
use Cpanel::SafeRun::Object               ();
use Cpanel::SafeDir                       ();
use Cpanel::SafeDir::MK                   ();
use Cpanel::SafeDir::RM                   ();
use Cpanel::SafeFind                      ();
use Cpanel::LoadFile                      ();
use Cpanel::Logger                        ();
use Cpanel::AdminBin                      ();
use Cpanel::DomainLookup                  ();
use Cpanel::HttpUtils::Htaccess           ();
use IPC::Open3                            ();
use Cpanel::Server::Type::Role::WebServer ();

my $ror_cache;

our $VERSION             = '1.1';
our $default_max_running = 4;
our $rails_version       = '2.3.18';

my $logger = Cpanel::Logger->new();

sub RoR_init {
    return if !Cpanel::Server::Type::Role::WebServer->is_enabled();

    read_from_admin('MOVEFILES');
    return 1;
}

sub get_default_max_running {
    return $default_max_running;
}

sub api2_needsimport {
    my $rordb_ref = read_from_admin('NEEDSIMPORT');
    my $rordb     = $rordb_ref->{'status'};

    $Cpanel::CPVAR{'ror_needsimport'} = ($rordb) ? 0 : 1;
}

sub api2_importrails {
    my $env = 0;    #production

    my $rordb_ref            = read_from_admin('NEEDSIMPORT');
    my $does_not_need_import = $rordb_ref->{'status'};

    if ($does_not_need_import) {
        return;
    }

    my @rorimports;
    Cpanel::SafeFind::find(
        {
            wanted => sub {
                if ( $File::Find::name =~ /\/boot\.rb$/ ) {
                    my $isapp    = 0;
                    my $railsdir = $File::Find::name;
                    $railsdir =~ s/\/config\/boot\.rb$//g;
                    if ( $railsdir eq $File::Find::name ) { return; }
                    open( my $bootrb_fh, '<', $File::Find::name );
                    while ( readline($bootrb_fh) ) {
                        if (/rails/) { $isapp = 1; last; }
                    }
                    close($bootrb_fh);
                    if ( !$isapp ) { return; }
                    my $port = Cpanel::AdminBin::adminrun( 'ports', 'ASSIGN', '1' );
                    if ( !$port ) {
                        $Cpanel::CPERROR{'ror'} = "Sorry, there was an internal error while assigning a port for this app.";
                        return ( { 'status' => 0, 'statusmsg' => $Cpanel::CPERROR{'ror'} } );
                    }

                    _secure_rails_app($railsdir);

                    my @RD      = split( /\//, $railsdir );
                    my $appname = pop @RD;
                    push @rorimports,
                      {
                        'name'       => $appname,
                        'path'       => substr( $railsdir, length($Cpanel::abshomedir) ),
                        'port'       => $port,
                        'loadonboot' => 0,
                        'env'        => ( $env ? 'development' : 'production' )
                      };
                }
                elsif ( $File::Find::name =~ /\Q$Cpanel::abshomedir\E\/(?:\.cpanel|tmp|public_ftp|mail|ssl|logs|\.htpasswds|\.ssh)$/ ) {
                    $File::Find::prune = 1;
                }
            },
            'no_chdir' => 1
        },
        $Cpanel::abshomedir
    );

    my $rorstore = read_from_admin('RAILSDBREAD');
    if ( !$rorstore ) {
        $rorstore = [];
    }
    push @{$rorstore}, @rorimports;
    return write_to_admin( 'RAILSDBWRITE', $rorstore );
}

sub api2_addapp {
    my %OPTS = @_;

    my $appname    = $OPTS{'appname'};
    my $loadonboot = int $OPTS{'loadonboot'};
    my $env        = int $OPTS{'env'};
    my $path       = Cpanel::SafeDir::safedir( $OPTS{'path'} );

    if ( $path eq $Cpanel::abshomedir || $path eq $Cpanel::homedir ) {
        $Cpanel::CPERROR{'ror'} = "Sorry, you cannot install a rails app in your home directory.  You must install it in a sub directory.";
        return ( { 'status' => 0, 'statusmsg' => $Cpanel::CPERROR{'ror'} } );
    }

    if ( -e $path ) {
        $Cpanel::CPERROR{'ror'} = "Sorry, that Application path is already taken.";
        return ( { 'status' => 0, 'statusmsg' => $Cpanel::CPERROR{'ror'} } );
    }
    else {
        Cpanel::SafeDir::MK::safemkdir( $path, '0755' );
    }

    if ( !-d $path ) {
        $Cpanel::CPERROR{'ror'} = "Sorry, the directory you selected for your app could not be created.";
        return ( { 'status' => 0, 'statusmsg' => $Cpanel::CPERROR{'ror'} } );
    }
    if ( !defined $appname ) {
        $Cpanel::CPERROR{'ror'} = "Sorry, you must provide a name for your application.";
        return ( { 'status' => 0, 'statusmsg' => $Cpanel::CPERROR{'ror'} } );
    }

    my $papp = _getapp($appname);
    if ($papp) {
        $Cpanel::CPERROR{'ror'} = "Sorry, that appname is already taken.";
        return ( { 'status' => 0, 'statusmsg' => $Cpanel::CPERROR{'ror'} } );
    }

    chdir $path || do {
        $Cpanel::CPERROR{'ror'} = "Unable to chdir into $path: $!";
        return ( { 'status' => 0, 'statusmsg' => $Cpanel::CPERROR{'ror'} } );
    };

    my $rails_output = Cpanel::SafeRun::Errors::saferunallerrors( 'rails', '_' . $rails_version . '_', '--force', '.' );
    if ( $rails_output =~ /Gem::LoadError/ms ) {

        my $message_queued = 0;
        if ( $rails_output =~ m/could not find rails/ims ) {
            if ( $rails_output =~ m/rails-([\d\.]+)[,\]]/ms ) {
                $Cpanel::CPERROR{'ror'} = "Rails version $1 is installed. However, version $rails_version is required. Please contact your web hosting provider to have Rails updated.";
                $message_queued = 1;
            }
        }
        else {
            $Cpanel::CPERROR{'ror'} = "An unknown error was encountered when creating your rails application.";
            $message_queued = 1;
        }

        Cpanel::SafeDir::RM::safermdir($path);
        if ( -e $path ) {
            if ($message_queued) {
                $Cpanel::CPERROR{'ror'} .= " Unable to remove application path";
            }
            else {
                $Cpanel::CPERROR{'ror'} = "Unable to remove application path";
            }
        }

        return ( { 'status' => 0, 'statusmsg' => $Cpanel::CPERROR{'ror'} } );
    }

    my $port = Cpanel::AdminBin::adminrun( 'ports', 'ASSIGN', '1' );
    if ( !$port ) {
        $Cpanel::CPERROR{'ror'} = "Sorry, there was an internal error while assigning a port for this app.";
        return ( { 'status' => 0, 'statusmsg' => $Cpanel::CPERROR{'ror'} } );
    }
    my $appdir = substr( $path, length($Cpanel::abshomedir) );

    my $rorstore = read_from_admin('RAILSDBREAD');
    if ( !$rorstore ) {
        $rorstore = [];
    }
    push @{$rorstore},
      {
        'name'       => $appname,
        'path'       => $appdir,
        'port'       => $port,
        'loadonboot' => $loadonboot,
        'env'        => ( $env ? 'development' : 'production' )
      };

    write_to_admin( 'RAILSDBWRITE', $rorstore );

    ${$rorstore}[ $#{$rorstore} ]->{'status'}    = 1;
    ${$rorstore}[ $#{$rorstore} ]->{'statusmsg'} = 'App Added';

    ${$rorstore}[ $#{$rorstore} ]->{'installdetails'} = $rails_output;

    _secure_rails_app($path);

    return [ ${$rorstore}[ $#{$rorstore} ] ];
}

sub api2_removeapp {
    my %OPTS = @_;

    my $appname = $OPTS{'appname'};
    if ( !defined $appname ) {
        $Cpanel::CPERROR{'ror'} = "Sorry, you cannot delete an application if you do not specify its name.";
        return ( { 'status' => 0, 'statusmsg' => $Cpanel::CPERROR{'ror'} } );
    }

    my $port;
    my $rorstore = read_from_admin('RAILSDBREAD');
    my $deadapp;
    my $deadappnum = 0;
    foreach my $app ( @{$rorstore} ) {
        if ( $app->{'name'} eq $appname ) {
            $port    = $app->{'port'};
            $deadapp = $app;
            last();
        }
        $deadappnum++;
    }
    if ( !$port ) {
        $Cpanel::CPERROR{'ror'} = "Sorry, that rails app ($appname) could not be found.";
        return ( { 'status' => 0, 'statusmsg' => $Cpanel::CPERROR{'ror'} } );
    }

    # Terminate any running instances
    _appcommand( 'appname' => $appname, 'command' => 'stop' );

    my $remport = Cpanel::AdminBin::adminrun( 'ports', 'REMOVE', $port );
    splice( @{$rorstore}, $deadappnum, 1 );

    my $ror_rewrite_store = read_from_admin('REWRITEREAD');
    if ( @{$ror_rewrite_store} ) {
        foreach my $rule ( @{$ror_rewrite_store} ) {
            if ( $rule->{'appname'} eq $appname ) {
                api2_removerewrite( 'rewriteurl' => $rule->{'url'}, 'rewritedomain' => $rule->{'domain'}, 'appname' => $rule->{'appname'} );
            }
        }
    }

    write_to_admin( 'RAILSDBWRITE', $rorstore );

    $deadapp->{'status'}    = 1;
    $deadapp->{'statusmsg'} = 'App Removed';

    return [$deadapp];
}

sub api2_stopapp {
    my %OPTS    = @_;
    my $appname = $OPTS{'appname'};
    return _appcommand( 'appname' => $appname, 'command' => 'stop' );
}

sub api2_startapp {
    my %OPTS        = @_;
    my $appname     = $OPTS{'appname'};
    my $max_running = $default_max_running;
    if ( $Cpanel::CPDATA{'MAXMONGREL'} ) {
        if ( $Cpanel::CPDATA{'MAXMONGREL'} =~ m/unlimited/i ) {
            $max_running = 'unlimited';
        }
        else {
            $max_running = int( $Cpanel::CPDATA{'MAXMONGREL'} );
        }
    }
    if ( $max_running ne 'unlimited' ) {
        my $ror_running = api2_listapps();
        my $count       = 0;
        foreach my $ror ( @{$ror_running} ) {
            if ( $ror->{'running'} ) {
                $count++;
            }
        }
        if ( $count >= $max_running ) {
            $Cpanel::CPERROR{'ror'} = "Sorry, you can not start additional applications. Your limit is currently $max_running";
            return ( { 'status' => 0, 'statusmsg' => "Sorry, you can not start additional applications. Your limit is currently $max_running", } );
        }
    }
    return _appcommand( 'appname' => $appname, 'command' => 'start' );
}

sub api2_restartapp {
    my %OPTS    = @_;
    my $appname = $OPTS{'appname'};
    return _appcommand( 'appname' => $appname, 'command' => 'restart' );
}

sub api2_softrestartapp {
    my %OPTS    = @_;
    my $appname = $OPTS{'appname'};
    return _appcommand( 'appname' => $appname, 'command' => 'softrestart' );
}

sub api2_changeapp {
    my %OPTS    = @_;
    my $appname = $OPTS{'appname'};
    if ( !$appname ) {
        $Cpanel::CPERROR{'ror'} = "Sorry, you cannot delete an application if you do not specify its name.";
        return ( { 'status' => 0, 'statusmsg' => $Cpanel::CPERROR{'ror'} } );
    }
    my $setapp = 0;

    my $rorstore = read_from_admin('RAILSDBREAD');
    for ( my $i = 0; $i <= $#{$rorstore}; $i++ ) {
        if ( ${$rorstore}[$i]->{'name'} eq $appname ) {
            if ( $OPTS{'newappname'} )            { ${$rorstore}[$i]->{'name'}       = $OPTS{'newappname'} }
            if ( defined $OPTS{'env'} )           { ${$rorstore}[$i]->{'env'}        = ( $OPTS{'env'} ? 'development' : 'production' ) }
            if ( defined $OPTS{'newloadonboot'} ) { ${$rorstore}[$i]->{'loadonboot'} = $OPTS{'newloadonboot'}; }

            $setapp = 1;
            last();
        }
    }
    if ( !$setapp ) {
        $Cpanel::CPERROR{'ror'} = "Sorry, that rails app ($appname) could not be found.";
        return ( { 'status' => 0, 'statusmsg' => $Cpanel::CPERROR{'ror'} } );
    }
    write_to_admin( 'RAILSDBWRITE', $rorstore );
    return ( { 'status' => 1, 'statusmsg' => 'New Settings Saved' } );
}

sub api2_listapps {
    if ($ror_cache) { return $ror_cache; }
    my %OPTS = @_;

    my $ror_store = read_from_admin('RAILSDBREAD');
    if ( !$ror_store || ref $ror_store ne 'ARRAY' ) {
        return;
    }
    for ( my $appcnt = 0; $appcnt <= $#{$ror_store}; $appcnt++ ) {
        my $pidfile = $Cpanel::abshomedir . '/' . ${$ror_store}[$appcnt]->{'path'} . '/log/mongrel.pid';
        my $pid     = Cpanel::LoadFile::loadfile($pidfile);
        if ( $pid =~ m/(\d+)/ ) {
            $pid = $1;
        }
        else {
            $pid = 0;
        }
        ${$ror_store}[$appcnt]->{'pid'} = $pid;
        if ( $pid && kill( 0, $pid ) ) {
            $Cpanel::CPVAR{ 'rorappstatus-' . ${$ror_store}[$appcnt]->{'name'} } = 1;
            ${$ror_store}[$appcnt]->{'running'} = 1;
        }
        else {
            $Cpanel::CPVAR{ 'rorappstatus-' . ${$ror_store}[$appcnt]->{'name'} } = 0;
            ${$ror_store}[$appcnt]->{'running'} = 0;
        }
        ${$ror_store}[$appcnt]->{'production'} = ( ( defined ${$ror_store}[$appcnt]->{'env'} && ${$ror_store}[$appcnt]->{'env'} eq 'development' ) ? 0 : 1 );
    }
    my @ror_store_copy = @{$ror_store};
    $ror_cache = \@ror_store_copy;
    return $ror_store;
}

sub api2_listrewrites {

    my $ror_rewrite_store = read_from_admin('REWRITEREAD');
    if ( !$ror_rewrite_store || ref $ror_rewrite_store ne 'ARRAY' ) {
        return;
    }
    for ( my $i = 0; $i < $#{$ror_rewrite_store}; $i++ ) {
        ${$ror_rewrite_store}[$i]->{'count'} = $i;
    }
    return $ror_rewrite_store;
}

sub _createrewriterule {
    my $domain        = shift;
    my $url           = shift;
    my $port          = shift;
    my $domaindocroot = shift;
    return Cpanel::HttpUtils::Htaccess::setupredirection(
        'docroot'     => $domaindocroot,
        'domain'      => $domain,
        'redirecturl' => "http://127.0.0.1:$port/",
        'code'        => 301,
        'matchurl'    => $url . '/(.*)',
        'rewriteopts' => 'P,L'
    );
}

sub _removerewriterule {
    my $domain        = shift;
    my $url           = shift;
    my $port          = shift;
    my $domaindocroot = shift;
    return Cpanel::HttpUtils::Htaccess::disableredirection( $domaindocroot, $domain, $url . '(.*)', "http://127.0.0.1:$port/", );
}

sub api2_setuprewrite {
    my %OPTS = @_;

    my $rewriteurl    = $OPTS{'rewriteurl'};
    my $rewritedomain = $OPTS{'rewritedomain'};
    my $appname       = $OPTS{'appname'};

    my $app = _getapp($appname);
    if ( !$app ) {
        $Cpanel::CPERROR{'ror'} = "Sorry, that rails app ($appname) could not be found.";
        return ( { 'status' => 0, 'statusmsg' => $Cpanel::CPERROR{'ror'} } );
    }
    $Cpanel::CPVAR{'ror_app_port'} = $app->{'port'};
    my $appdir     = $app->{'path'};
    my $fullappdir = Cpanel::SafeDir::safedir( $app->{'path'} );
    my $port       = $app->{'port'};
    my ( $domaindocroot, $relroot ) = Cpanel::DomainLookup::getdocroot($rewritedomain);

    my $ror_rewrite_store = read_from_admin('REWRITEREAD');
    if ( !$ror_rewrite_store ) {
        $ror_rewrite_store = [];
    }
    if ( $rewriteurl =~ /^\// ) { $rewriteurl =~ s/^\///g; }
    push @{$ror_rewrite_store},
      {
        'url'             => $rewriteurl,
        'appname'         => $appname,
        'port'            => $port,
        'domain'          => $rewritedomain,
        'rewritebasepath' => $domaindocroot
      };
    my ( $status, $msg ) = _createrewriterule( $rewritedomain, $rewriteurl, $port, $domaindocroot );

    my $result;

    if ($status) {
        write_to_admin( 'REWRITEWRITE', $ror_rewrite_store );
        $result = {
            'status'    => $status,
            'statusmsg' => $status ? 'Added Rewrite' : $msg,
            %{ ${$ror_rewrite_store}[ $#{$ror_rewrite_store} ] }
        };
    }
    else {
        $result = {
            'status'    => $status,
            'statusmsg' => $status ? 'Added Rewrite' : $msg,
        };
    }

    return $result;
}

sub api2_removerewrite {
    my %OPTS = @_;

    my $rewriteurl    = $OPTS{'rewriteurl'};
    my $rewritedomain = $OPTS{'rewritedomain'};
    my $appname       = $OPTS{'appname'};

    my $app = _getapp($appname);
    if ( !$app ) {
        $Cpanel::CPERROR{'ror'} = "Sorry, that rails app ($appname) could not be found.";
        return ( { 'status' => 0, 'statusmsg' => $Cpanel::CPERROR{'ror'} } );
    }

    my $appdir     = $app->{'path'};
    my $fullappdir = Cpanel::SafeDir::safedir( $app->{'path'} );
    my $port       = $app->{'port'};
    my ( $domaindocroot, $relroot ) = Cpanel::DomainLookup::getdocroot($rewritedomain);

    my $ror_rewrite_store = read_from_admin('REWRITEREAD');
    my $deadrewrite;
    my $deadrewritenum = 0;
    foreach my $rewrite ( @{$ror_rewrite_store} ) {
        if (   $rewrite->{'domain'} eq $rewritedomain
            && $rewrite->{'appname'} eq $appname
            && $rewrite->{'url'} eq $rewriteurl ) {
            $deadrewrite = $rewrite;
            last();
        }
        $deadrewritenum++;
    }
    if ( !$deadrewrite ) {
        $Cpanel::CPERROR{'ror'} = "Sorry, that rails app rewrite could not be found.";
        return ( { 'status' => 0, 'statusmsg' => $Cpanel::CPERROR{'ror'} } );
    }
    splice( @{$ror_rewrite_store}, $deadrewritenum, 1 );

    my ( $status, $msg ) = _removerewriterule( $rewritedomain, $rewriteurl, $port, $domaindocroot );
    my $result;

    if ($status) {
        write_to_admin( 'REWRITEWRITE', $ror_rewrite_store );
        $result = {
            'status'    => $status,
            'statusmsg' => $status ? 'Added Rewrite' : $msg,
            %{$deadrewrite}
        };
    }
    else {
        $result = {
            'status'    => $status,
            'statusmsg' => $status ? 'Added Rewrite' : $msg,
        };
    }

    return $result;
}

sub _appcommand {
    my %OPTS = @_;

    my $appname = $OPTS{'appname'};
    my $command = $OPTS{'command'};
    if ( !defined $appname ) {
        $Cpanel::CPERROR{'ror'} = "Sorry, you cannot make changes to an application if you do not specify its name.";
        return ( { 'status' => 0, 'statusmsg' => $Cpanel::CPERROR{'ror'} } );
    }
    my $app = _getapp($appname);
    if ( !$app ) {
        $Cpanel::CPERROR{'ror'} = "Sorry, that rails app ($appname) could not be found.";
        return ( { 'status' => 0, 'statusmsg' => $Cpanel::CPERROR{'ror'} } );
    }

    my $appdir   = $app->{'path'};
    my ($port)   = $app->{'port'} =~ /^(\d+)$/;
    my ($appenv) = $app->{'env'}  =~ /^(production|development)$/;
    $appenv ||= 'production';

    $appdir = Cpanel::SafeDir::safedir($appdir);
    $appdir =~ /(.*)/;
    $appdir = $1;
    chdir $appdir || do {
        $Cpanel::CPERROR{'ror'} = "Could not chdir to $appdir";
        return ( { 'status' => 0, 'statusmsg' => "Could not chdir to $appdir" } );
    };
    my $pidfile = $Cpanel::abshomedir . '/' . $app->{'path'} . '/log/mongrel.pid';
    $pidfile =~ /(.*)/;
    $pidfile = $1;
    my $pid = Cpanel::LoadFile::loadfile($pidfile);
    my $runner_obj;

    # this really should be broken out into an object model somewhere
    if ( $command eq 'start' ) {
        if ( $pid =~ /(\d+)/ && !kill( 0, $1 ) ) {
            unlink($pidfile);
        }

        $runner_obj = Cpanel::SafeRun::Object->new(
            'program' => 'mongrel_rails',
            'args'    => [
                'start', '-p', $port, '-d', '-e', $appenv, '-P',
                'log/mongrel.pid'
            ],
        );
    }
    elsif ( $command eq 'stop' ) {
        $runner_obj = Cpanel::SafeRun::Object->new(
            'program' => 'mongrel_rails',
            'args'    => ['stop'],
        );
    }
    elsif ( $command eq 'restart' ) {
        $runner_obj = Cpanel::SafeRun::Object->new(
            'program' => 'mongrel_rails',
            'args'    => ['restart'],
        );
    }
    elsif ( $command eq 'softrestart' ) {
        $runner_obj = Cpanel::SafeRun::Object->new(
            'program' => 'mongrel_rails',
            'args'    => [ 'stop', '-s' ],
        );
    }

    # TODO: why is this in here twice?
    elsif ( $command eq 'stop' ) {
        if ( $pid =~ /(\d+)/ ) {
            kill( 9, $1 );
        }
    }
    else {
        $Cpanel::CPERROR{'ror'} = "Invalid command '$command' specified.";
        return (
            {
                'status'    => 0,
                'statusmsg' => "Invalid command '$command' specified."
            }
        );
    }

    my $status = $runner_obj->CHILD_ERROR() ? 0 : 1;

    # TODO: If we have an error here, should status be set to 1?
    if ( $runner_obj->stderr ne '' ) {
        $Cpanel::CPERROR{'ror'} = $runner_obj->stderr;
        $logger->info( $runner_obj->stderr );
    }

    return (
        {
            'status'         => $status,
            'statusmsg'      => $command . ' ok',
            'mongrel_stdout' => $runner_obj->stdout,
            'mongrel_stderr' => $runner_obj->stderr,
        }
    );
}

sub _getapp {
    my $appname = shift;

    my $rorstore = read_from_admin('RAILSDBREAD');
    my $rapp;
    foreach my $app ( @{$rorstore} ) {
        if ( $app->{'name'} eq $appname ) {
            $rapp = $app;
            last();
        }
    }
    return $rapp;
}

my $web_server_role_allow_demo = { needs_role => "WebServer", allow_demo => 1 };
my $web_server_role_deny_demo  = { needs_role => "WebServer" };

our %API = (
    needsimport    => $web_server_role_allow_demo,
    importrails    => $web_server_role_allow_demo,
    addapp         => $web_server_role_deny_demo,
    removeapp      => $web_server_role_deny_demo,
    changeapp      => $web_server_role_allow_demo,
    listrewrites   => $web_server_role_allow_demo,
    setuprewrite   => $web_server_role_deny_demo,
    removerewrite  => $web_server_role_deny_demo,
    listapps       => $web_server_role_allow_demo,
    stopapp        => $web_server_role_deny_demo,
    startapp       => $web_server_role_deny_demo,
    restartapp     => $web_server_role_deny_demo,
    softrestartapp => $web_server_role_allow_demo,
);

sub api2 {
    my ($func) = @_;
    return { %{ $API{$func} } } if $API{$func};
    return;
}

sub _secure_rails_app {
    my ($path) = @_;
    foreach my $dir (qw<app config db doc lib script test tmp vendor>) {
        my $htaccess_file = "$path/$dir/.htaccess";
        ($htaccess_file) = $htaccess_file =~ /(\S*)/;
        if ( !-e $htaccess_file ) {
            if ( open( my $fh, '>', $htaccess_file ) ) {
                print {$fh} _htaccess();
                close($fh);
            }
        }
    }
    return;
}

sub _htaccess {
    return <<'EOF';
<Limit GET POST OPTIONS PROPFIND>
    Order allow,deny
    Deny from all
</Limit>
EOF
}

sub read_from_admin {
    my ($action) = @_;

    return Cpanel::AdminBin::adminfetchnocache( 'rails', '', $action, 'storable' ) || [];
}

sub write_to_admin {
    my ( $action, $rorstore ) = @_;
    Cpanel::AdminBin::adminstor( 'rails', $action, $rorstore );
}

1;
