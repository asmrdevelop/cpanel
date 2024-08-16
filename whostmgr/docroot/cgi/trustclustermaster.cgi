#!/usr/local/cpanel/3rdparty/bin/perl
# cpanel - whostmgr/docroot/cgi/trustclustermaster.cgi
#                                                  Copyright 2009 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::Form               ();
use Cpanel::Hostname           ();
use Cpanel::Accounting         ();
use Cpanel::Encoder::Tiny      ();
use Cpanel::Ips::Fetch         ();
use Cpanel::Logger             ();
use Cpanel::Version::Full      ();
use Whostmgr::HTMLInterface    ();
use Whostmgr::DNS::Cluster     ();
use Whostmgr::DNS::Cluster::UI ();
use Cpanel::PwCache            ();
use Cpanel::LoadModule         ();
use Cpanel::DNSLib::PeerConfig ();    # PPI USE OK ~ We can't rely on customer config modules to set this up right

## no critic(RequireUseWarnings)

# init_app() will init ACLS and verify we have the
# cluster acl.  TODO: Refactor all the cgis
# to use Whostmgr::CgiApp::DnsCluster
Whostmgr::DNS::Cluster::UI::init_app(1);
my %FORM = Cpanel::Form::parseform();

my $logger;

my $cluster_user = Whostmgr::DNS::Cluster::get_validated_cluster_user_from_formenv( $FORM{'cluster_user'}, $ENV{'REMOTE_USER'} );

Whostmgr::DNS::Cluster::UI::render_cluster_masquerade_include_if_available($cluster_user);

my $homedir      = Cpanel::PwCache::gethomedir($cluster_user);
my $selfhostname = Cpanel::Hostname::gethostname();
my $selfversion  = Cpanel::Version::Full::getversion();

# Validate host parameter
my $clustermaster = $FORM{'clustermaster'};
$clustermaster =~ s/\///g;
$clustermaster =~ s/\.\.//g;
$clustermaster =~ tr/\r\n\f\0//d;
$clustermaster =~ s/^\s+//g;
$clustermaster =~ s/\s+$//g;
my $hostname = $clustermaster;
$FORM{host} = $hostname;

if ( $clustermaster !~ /^\d+\.\d+\.\d+\.\d+$/ ) {
    if ( my $inetaddr = gethostbyname($clustermaster) ) {
        require Socket;
        $clustermaster = Socket::inet_ntoa($inetaddr);
    }
    else {
        # Adding this logger statement to better indicate failures to connect in reverse trust relationship setup. CPANEL-6911
        _logger()->warn("DNS lookup failed for $clustermaster while attempting to establish a remote DNS Trust Relationship.");
        Whostmgr::DNS::Cluster::UI::fatal_error_and_exit("Dns Lookup Failed for $clustermaster");
    }
}

# Validate the user parameter

my $user = $FORM{'user'};
$user =~ tr/\r\n\f\0//d;
$user =~ s/^\s+//g;
$user =~ s/\s+$//g;

Whostmgr::DNS::Cluster::UI::fatal_error_and_exit("Invalid user given") if !$user;

# Validate the pass parameter

my $pass = $FORM{'pass'};
$pass =~ tr/\r\n\f\0//d;
$pass =~ s/^\s*\-+BEGIN\s+WHM\s+ACCESS\s+KEY\-+//g;
$pass =~ s/\-+END\s+WHM\s+ACCESS\s+KEY\-+\s*$//g;
$pass =~ s/^\s+//g;
$pass =~ s/\s+$//g;
Whostmgr::DNS::Cluster::UI::fatal_error_and_exit("Invalid access hash given") if !$pass;

if ( grep { $_ eq $clustermaster } Cpanel::Ips::Fetch::fetchipslist() ) {
    Whostmgr::DNS::Cluster::UI::fatal_error_and_exit("The specified IP address would create a cyclic trust relationship: $clustermaster.");
}

my $whm = Cpanel::Accounting->new(
    'host'            => $clustermaster,
    'usessl'          => 1,
    'ssl_verify_mode' => 0,
    'user'            => $cluster_user,
    'accesshash'      => $pass,
);

my $version = $whm->version();
if ( $whm->{'error'} ) {
    if ( $whm->{'error'} =~ /401/ ) {
        Whostmgr::DNS::Cluster::UI::fatal_error_and_exit("The remote server did not accept the access hash.  Please verify the access hash and username and try again.  The exact message was $whm->{'error'}.  For more information check /usr/local/cpanel/logs/login_log on the remote server.");
    }
    Whostmgr::DNS::Cluster::UI::fatal_error_and_exit("There was an error while processing your request: Cpanel::Accounting returned [$whm->{'error'}]");
}

# Check version
my ( $majorv, $minorv, $rev ) = split( /\./, $version );
if ( $majorv < 6 ) {
    Whostmgr::DNS::Cluster::UI::fatal_error_and_exit("This operation requires the remote server to be running WHM 6.0 or later.  The server reported version: $version");
}

$FORM{module} ||= 'cPanel';
my $pm = $FORM{module};
$FORM{dnsrole} = 'standalone';

my $namespace = "Cpanel::NameServer::Setup::Remote::$pm";
Cpanel::LoadModule::load_perl_module($namespace);

my ( $status, $statusmsg, $notices, $servername );
{
    # TODO:
    #
    # Setting $ENV{'REMOTE_USER'} is a workaround to ensure all third party
    # Cpanel::NameServer::Setup::Remote modules continue to work
    #
    # We should come up with a better method to pass the user to
    # setup the nameserver remote for in the future
    #
    local $@;
    local $ENV{'REMOTE_USER'} = $cluster_user;

    # Eval 'just in case'
    ( $status, $statusmsg, $notices, $servername ) = eval { $namespace->setup(%FORM) };

    if ( !$status ) {
        $statusmsg ||= $@;

        print qq{<div class="errormsg" id="trustRelationshipFailed">The trust relationship could not be established, please examine /usr/local/cpanel/logs/error_log for more information.<br />} . join( '<br />', split( /\n/, Cpanel::Encoder::Tiny::safe_html_encode_str($statusmsg) ) ) . qq{</div>};
        warn "Could not write DNS trust configuration file: $!";
        Whostmgr::HTMLInterface::sendfooter();
        exit;
    }
    print qq{<br /><br /><div class="okmsg" id="trustRelationshipFailed">The trust relationship has been established from the remote server to this server.</div>};
}

Whostmgr::HTMLInterface::sendfooter();
exit;

sub _logger {
    return $logger ||= Cpanel::Logger->new();
}
