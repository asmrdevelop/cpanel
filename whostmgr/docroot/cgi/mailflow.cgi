#!/usr/local/cpanel/3rdparty/bin/perl

# cpanel - whostmgr/docroot/cgi/mailflow.cgi       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
# 1. Redistributions of source code must retain the above copyright notice,
# this list of conditions and the following disclaimer.
#
# 2. Redistributions in binary form must reproduce the above copyright notice,
# this list of conditions and the following disclaimer in the documentation
# and/or other materials provided with the distribution.
#
# 3. Neither the name of the owner nor the names of its contributors may be
# used to endorse or promote products derived from this software without
# specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
# SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
# CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
# OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

use strict;
use warnings;

# The flowchart creation needs this to avoid overencoding text.
use utf8;

use Graph::Flowchart;
use Graph::Easy;
use Cpanel::Config::LoadCpConf ();
use Cpanel::Form               ();
use Cpanel::Exim::Config::Def  ();
use Cpanel::Binaries           ();
use Whostmgr::ACLS             ();
use Whostmgr::HTMLInterface    ();

print "Content-type: text/html; charset=utf-8\r\n\r\n";

_check_acls();

#print qq{<pre>};

my %FORM = Cpanel::Form::parseform();
my %OPTS;
my $cpconf = Cpanel::Config::LoadCpConf::loadcpconf();

my $clam = 0;
if ( -x Cpanel::Binaries::path("clamd") && -e "/etc/exim.conf.mailman2.exiscan.dist" ) {
    $clam = 1;
}
my @DEFAULT_RBL_ACLS = ( 'spamhaus_rbl', 'spamcop_rbl', 'spamhaus_spamcop_rbl', );
my $globalsa         = ( -e '/etc/global_spamassassin_enable' ? 1 : 0 );
my $senderverify     = 1;
my $callouts         = 1;
my $systemfilter     = '/etc/cpanel_exim_system_filter';
my $setsenderheader  = 0;
my $hasboxtrapper    = $cpconf->{'skipboxtrapper'} ? 0 : 1;
my %ACLBLOCKS;
my %ACLINSERTS;
my %FILTERS;
my %ACLS;

if ( opendir my $acls_opts, '/usr/local/cpanel/etc/exim/acls' ) {
    while ( my $aclsblock = readdir $acls_opts ) {
        next if ( $aclsblock =~ /^\./ );
        if ( opendir my $acls_iopts, '/usr/local/cpanel/etc/exim/acls/' . $aclsblock ) {
            while ( my $acl = readdir $acls_iopts ) {
                next if $acl =~ m/^\./;
                $ACLS{$acl} = 1;
                push @{ $ACLBLOCKS{$aclsblock} }, $acl;
            }
            closedir $acls_iopts;
        }
    }
    closedir $acls_opts;
}

foreach my $acl (@Cpanel::Exim::Config::Def::OFF_DEFAULT_ACLS) {
    $ACLS{$acl} = 0;
}

if ( opendir my $filter_opts, '/usr/local/cpanel/etc/exim/sysfilter/options' ) {
    while ( my $filter = readdir $filter_opts ) {
        next if $filter =~ m/^\./;
        $FILTERS{$filter} = 1;
    }
    closedir $filter_opts;
}

foreach my $filter (@Cpanel::Exim::Config::Def::OFF_DEFAULT_FILTERS) {
    $FILTERS{$filter} = 0;
}

if ( $FORM{'use_form'} ) {
    %OPTS = %FORM;
    delete $OPTS{'use_form'};
}
else {
    open( EXIMCOPTS, '/etc/exim.conf.localopts' );
    while (<EXIMCOPTS>) {
        chomp();
        my ( $opt, $value ) = split( /=/, $_ );
        $OPTS{$opt} = $value;
    }
    close(EXIMCOPTS);
}
my @custom_rbls;
foreach my $opt ( keys %OPTS ) {
    my $value = $OPTS{$opt};
    if ( $opt =~ m/^acl_(\S+)/ ) {
        my $acl = $1;
        if ( $value eq '0' ) { $ACLS{$acl} = 0; }
        if ( $value eq '1' ) { $ACLS{$acl} = 1; }
        if ( $acl =~ m/_rbl$/ && !grep { $acl eq $_ } @DEFAULT_RBL_ACLS ) {
            push @custom_rbls, $acl;
        }
    }
    elsif ( $opt =~ /^filter_(\S+)/ ) {
        if ( $value eq '0' ) { $FILTERS{$1} = 0; }
        if ( $value eq '1' ) { $FILTERS{$1} = 1; }
    }
    elsif ( $opt eq 'callouts' && $value eq '0' )        { $callouts        = 0; }
    elsif ( $opt eq 'senderverify' && $value eq '0' )    { $senderverify    = 0; }
    elsif ( $opt eq 'setsenderheader' && $value eq '1' ) { $setsenderheader = 1; }
    elsif ( $opt eq 'systemfilter' )                     { $systemfilter    = $value; }
}

my $chart  = Graph::Flowchart->new();
my $format = shift || 'as_html_page';
my $current;

sub Graph::Flowchart::add_if_end {
    my ( $self, $if, $end, $where ) = @_;

    $if  = $self->new_block( $if,  Graph::Flowchart::N_IF() )  unless ref $if;
    $end = $self->new_block( $end, Graph::Flowchart::N_END() ) unless ref $end;

    $where = $self->{_cur} unless defined $where;

    $if = $self->insert_block( $if, $where );

    $self->connect( $if, $end, 'true', 'true' );

    my $joint = $self->add_joint;

    $self->connect( $if, $joint, 'false', 'false' );

    $self->{_cur} = $joint;

    return ( $if, $end, $self->{_cur} ) if wantarray;

    $self->{_cur};
}

sub Graph::Flowchart::add_if_not_end {
    my ( $self, $if, $end, $where ) = @_;

    $if  = $self->new_block( $if,  Graph::Flowchart::N_IF() )  unless ref $if;
    $end = $self->new_block( $end, Graph::Flowchart::N_END() ) unless ref $end;

    $where = $self->{_cur} unless defined $where;

    $if = $self->insert_block( $if, $where );

    $self->connect( $if, $end, 'false', 'false' );

    my $joint = $self->add_joint;

    $self->connect( $if, $joint, 'true', 'true' );

    $self->{_cur} = $joint;

    return ( $if, $end, $self->{_cur} ) if wantarray;

    $self->{_cur};
}

sub Graph::Flowchart::add_if_not_then {
    my ( $self, $if, $then, $where ) = @_;

    $if   = $self->new_block( $if,   Graph::Flowchart::N_IF() )   unless ref $if;
    $then = $self->new_block( $then, Graph::Flowchart::N_THEN() ) unless ref $then;

    $where = $self->{_cur} unless defined $where;

    $if = $self->insert_block( $if, $where );

    $self->connect( $if, $then, 'false', 'false' );

    # then --> '*'
    $self->{_cur} = $self->add_joint($then);

    # if -- true --> '*'
    $self->connect( $if, $self->{_cur}, 'true', 'true' );

    return ( $if, $then, $self->{_cur} ) if wantarray;

    $self->{_cur};
}

$chart->first_block("Incoming Email via SMTP");
$current = $chart->add_if_end( 'Mail is a Mailman bounce', 'accept' );
$current = $chart->add_if_not_end( 'Recipient Verification (The destination is a valid account.)', 'reject' );
$current = $chart->add_if_end( 'Sender Host is Authenticated (using SMTP AUTH)',        'accept' );
$current = $chart->add_if_end( 'Sender Host has done POP/IMAP before SMTP or is local', 'accept' );
if ( $ACLS{'spamcop_rbl'} ) {
    $current = $chart->add_if_end( 'Sender Host is in the RBL bl.spamcop.net', 'reject' );
}
if ( $ACLS{'spamhaus_rbl'} ) {
    $current = $chart->add_if_end( 'Sender Host is in the RBL zen.spamhaus.org', 'reject' );
}
if ( $ACLS{'spamhaus_spamcop_rbl'} ) {
    $current = $chart->add_if_end( 'Sender Host is in the RBL bl.spamcop.net or zen.spamhaus.org', 'reject' );
}

# Add custom RBLs
foreach my $rbl (@custom_rbls) {
    if ( $ACLS{$rbl} ) {
        my $rbl_name = $rbl;
        $rbl_name =~ s/_rbl$//;
        $current = $chart->add_if_end( 'Sender Host is in the RBL ' . $rbl_name, 'reject' );
    }
}

if ($senderverify) {
    if ($callouts) {
        $current = $chart->add_if_not_end( 'Sender Address can be verified using callouts', 'reject' );
    }
    else {
        $current = $chart->add_if_not_end( 'Sender Address can be verified', 'reject' );
    }
}
$current = $chart->add_if_end( 'Recipent Domain is local',                                   'accept' );
$current = $chart->add_if_end( 'Server is a backup mail exchanger for the Recipent Domain.', 'accept' );

if ( !$globalsa ) {
    $current = $chart->add_block('Scan mail with Apache SpamAssassin™ if enabled.');
}
else {
    $current = $chart->add_if_then( 'Apache SpamAssassin is enabled for recipient.', 'Scan mail with Apache SpamAssassin.' );
}
if ( $ACLS{'deny_spam_score_over_200'} ) {
    $current = $chart->add_if_end( 'Spam Score > 20.0.', 'reject' );
}
if ( $ACLS{'deny_spam_score_over_175'} ) {
    $current = $chart->add_if_end( 'Spam Score > 17.5.', 'reject' );
}
if ( $ACLS{'deny_spam_score_over_150'} ) {
    $current = $chart->add_if_end( 'Spam Score > 15.0.', 'reject' );
}
if ( $ACLS{'deny_spam_score_over_125'} ) {
    $current = $chart->add_if_end( 'Spam Score > 12.5.', 'reject' );
}
if ( $ACLS{'deny_spam_score_over_100'} ) {
    $current = $chart->add_if_end( 'Spam Score > 10.0.', 'reject' );
}

if ($clam) {
    $current = $chart->add_if_end( 'Message has a virus detected in it or other mailware', 'reject' );
}
my $end = $chart->new_block( 'accept', Graph::Flowchart::N_END() );
$end = $chart->add_block($end);
$chart->{_last} = $end;
my $start = $chart->{_first};

my $gr = $chart->as_graph();

$gr->set_attribute( 'node.if',    'fill',  'white' );
$gr->set_attribute( 'edge.true',  'color', 'green' );
$gr->set_attribute( 'edge.false', 'color', 'red' );
$gr->{att}->{graph}->{title} = 'Exim ACL Flowchart';

print STDERR "Resulting graph has ", scalar $gr->nodes(), " nodes and ", scalar $gr->edges(), " edges:\n\n";

binmode STDOUT, ':encoding(UTF-8)' or die("binmode STDOUT, ':encoding(UTF-8)' failed: $!");
print $gr->$format();

sub _check_acls {
    Whostmgr::ACLS::init_acls();

    if ( !Whostmgr::ACLS::hasroot() ) {
        Whostmgr::HTMLInterface::defheader( '', '', '/cgi/tweakcphulk.cgi' );
        print <<'EOM';

    <br />
    <br />
    <div><h1>Permission denied</h1></div>
    </body>
    </html>
EOM
        exit;
    }
}
