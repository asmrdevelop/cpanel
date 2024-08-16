package Cpanel::CSVImport;

# cpanel - Cpanel/CSVImport.pm                     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel                                   ();
use Cpanel::Email                            ();
use Cpanel::Email::Normalize::EmailLocalPart ();
use Cpanel::Encoder::Tiny                    ();
use Cpanel::LoadModule                       ();
use Cpanel::PasswdStrength::Generate         ();
use Cpanel::PipeHandler                      ();
use Cpanel::Rand::Get                        ();
use Cpanel::SafeDir::MK                      ();
use Cpanel::SafeStorable                     ();
use Cpanel::Validate::EmailRFC               ();

sub CSVImport_init { }

my $csvdata;
my $csvdatafile;
my %HEADERS = (
    'email' =>
      [ { 'keys' => [], 'shortname' => 'ignore', 'name' => 'Ignore' }, { 'keys' => [ 'email', 'user', 'name' ], 'shortname' => 'email', 'name' => 'Email' }, { 'keys' => [ 'pass', 'code' ], 'shortname' => 'password', 'name' => 'Password' }, { 'keys' => ['domain'], 'shortname' => 'domain', 'name' => 'Domain' }, { 'keys' => [ 'quota', 'disk' ], 'shortname' => 'quota', 'name' => 'Quota (MB)' } ],
    'fwd' => [ { 'keys' => [], 'shortname' => 'ignore', 'name' => 'Ignore' }, { 'keys' => ['source'], 'shortname' => 'source', 'name' => 'Source' }, { 'keys' => ['target'], 'shortname' => 'target', 'name' => 'Target' }, ]

);

sub CSVImport_doimport {
    my ( $id, $type, $domain ) = @_;
    return if ( !Cpanel::hasfeature('csvimport') );
    if ( $Cpanel::CPDATA{'DEMO'} eq '1' ) {
        print 'Sorry, this feature is disabled in demo mode.';
        return;
    }

    if ( !$domain ) {
        $domain = $Cpanel::CPDATA{'DNS'};
    }

    # Deal with very large imports.
    local $SIG{'PIPE'} = \&Cpanel::PipeHandler::pipeBGMgr;
    alarm(7200);

    $id =~ s/\///g;

    my $file       = $Cpanel::homedir . '/tmp/cpcsvimport/' . $id;
    my $importdata = Cpanel::SafeStorable::lock_retrieve( $file . '.import' );

    my $domhash  = { map { $_ => 1 } @Cpanel::DOMAINS };
    my $numrows  = scalar @$importdata;
    my $rowcount = 0;
    foreach my $row (@$importdata) {
        $rowcount++;
        my ( $status, $msg );
        if ( $type eq 'fwd' ) {
            ( $status, $msg ) = Cpanel::Email::addforward( $row->{'source'}, $row->{'target'}, $domain, 1, $domhash );
            print '<div class="statusline"><div class="statusitem">' . Cpanel::Encoder::Tiny::safe_html_encode_str("$row->{'source'} => $row->{'target'} ") . '</div><div class="status ' . ( $status ? 'green-status' : 'red-status' ) . '">' . $msg . '</div></div>' . "\n";
        }
        else {
            ( $status, $msg ) = Cpanel::Email::addpop( $row->{'email'}, $row->{'password'}, $row->{'quota'}, '', 0, 1 );
            print '<div class="statusline"><div class="statusitem">' . Cpanel::Encoder::Tiny::safe_html_encode_str( $row->{'email'} ) . '</div><div class="status ' . ( $status ? 'green-status' : 'red-status' ) . '">' . $msg . '</div></div>' . "\n";
        }
        print qq{<script>setcompletestatus($rowcount,$numrows)</script>\n\n};
    }

    return;
}

sub api2_processdata {
    my %OPTS = @_;

    Cpanel::LoadModule::load_perl_module('Cpanel::CSVImport::Process');

    my $id = $OPTS{'csvimportid'} // '';
    $id =~ s/\///g;

    my $file      = $Cpanel::homedir . '/tmp/cpcsvimport/' . $id;
    my $delimiter = $OPTS{'delimiter'} || ',';

    $csvdata = Cpanel::CSVImport::Process::process( $file, ( $OPTS{'colheader'} ? 1 : 0 ), substr( ( $delimiter =~ m/other/i ? $OPTS{'otherdelimiter'} : $delimiter ), 0, 64 ) );
    eval { Cpanel::SafeStorable::lock_nstore( $csvdata, $file . '.parsed' ); };

    if ($@) {
        $Cpanel::CPERROR{$Cpanel::context} = "Could not process data for CSV import id “$id”.";
    }
    else {
        $csvdatafile = $file;
    }

    return;
}

sub api2_loaddata {
    my %OPTS = @_;

    my $id = $OPTS{'csvimportid'};
    $id =~ s/\///g;

    if ( !length $id ) {
        $Cpanel::CPERROR{$Cpanel::context} = "“id” is a required field";
        return;
    }

    my $file = $Cpanel::homedir . '/tmp/cpcsvimport/' . $id;
    eval { $csvdata = Cpanel::SafeStorable::lock_retrieve( $file . '.parsed' ); };

    return if !$csvdata;
    $csvdatafile = $file;

    return;
}

sub api2_columnchoices {
    my %OPTS = @_;
    my $type = $OPTS{'type'} || 'email';

    #$csvdata->{'columns'}
    my $has_header_data = 0;
    if ( ref $csvdata->{'header'} && @{ $csvdata->{'header'} } ) {
        $has_header_data = 1;
    }

    my @RSD;
    if ( $csvdata && ref $csvdata ) {
        my $colNum = ( defined $csvdata->{'columns'} ) ? $csvdata->{'columns'} - 1 : -1;    #a value of -1 is necessary since 0 implies a single column exists
        my %USEDHEADERS;
        for ( my $col = $colNum; $col >= 0; $col-- ) {
            my $colname = '';
            if ($has_header_data) {
                my $guess_name = $csvdata->{'header'}[$col];
              HEADERM:
                foreach my $header ( @{ $HEADERS{$type} } ) {
                    next HEADERM if ( exists $USEDHEADERS{ $header->{'shortname'} } );
                    foreach my $match ( @{ $header->{'keys'} } ) {

                        if ( $guess_name =~ /\Q$match\E/i ) {
                            $colname = $header->{'shortname'};
                            last HEADERM;
                        }
                    }
                }

            }

            my @options;
            foreach my $header ( @{ $HEADERS{$type} } ) {

                #Once we add lang tags colname should be passed though the lang system
                push @options, { 'colshortname' => $header->{'shortname'}, 'colname' => $header->{'name'}, 'colselected' => ( $header->{'shortname'} eq $colname ? 'selected="selected"' : '' ) };
            }
            unshift @RSD, { 'num' => ( $col + 1 ), 'options' => \@options };

            $USEDHEADERS{$colname} = 1;
        }
    }
    return \@RSD;
}

sub api2_data {
    my %OPTS = @_;
    my $type = $OPTS{'type'} || 'email';

    my @RSD;
    if ( $csvdata && ref $csvdata ) {
        my $rowcount = 0;
        foreach my $row ( @{ $csvdata->{'data'} } ) {
            $rowcount++;
            my @rowdata;
            foreach my $col ( 0 .. ( $csvdata->{'columns'} - 1 ) ) {
                push @rowdata, { 'value' => $row->[$col] };
            }
            push @RSD, { 'num' => $rowcount, 'row' => \@rowdata };
        }
    }
    return \@RSD;
}

# Email and Forward importing.
#
# After talking with Vera, it was obvious that the rules for this need to be written
# down somewhere.
#
# The imported email addresses and 'source' for the forwards follow the same rules.
# 1. If the entry has a '@'
#    a. If the domain portion is owned by the user, keep it
#    b. Otherwise, replace the domain with the requested domain
# 2. The local part of the domain is scrubbed of any characters not allowed
#    for cPanel local parts.
#
# The target email address of a forward
# 1. If the entry has no '@', scrub the address to remove characters not allowed
#    for cPanel local parts.
# 2. Otherwise, treat as an RFC Email address and scrub accordingly.
sub api2_configimport {
    my %OPTS = @_;
    my $type = $OPTS{'type'} || 'email';

    if ( !$csvdatafile ) {
        $Cpanel::CPERROR{$Cpanel::context} = "No data file specified, loaddata or processdata must be called first.";
        return;
    }

    my %HEADERS;
    foreach my $key ( keys %Cpanel::FORM ) {
        next if ( $key !~ m/^header(\d+)/ );
        my $header      = $1;
        my $header_name = $Cpanel::FORM{$key};
        $HEADERS{$header} = $header_name;
    }

    my %MYDOMAINS = map { $_ => 1 } @Cpanel::DOMAINS;

    my @ROWS;
    if ( $csvdata && ref $csvdata ) {
        my $rowcount = 0;
        foreach my $row ( @{ $csvdata->{'data'} } ) {
            $rowcount++;
            my %ROWDATA;

            foreach my $col ( 0 .. ( $csvdata->{'columns'} - 1 ) ) {
                if ( !$HEADERS{ $col + 1 } || $HEADERS{ $col + 1 } eq 'ignore' ) { next; }

                $ROWDATA{ $HEADERS{ $col + 1 } } = $row->[$col];
            }

            if ( $type eq 'email' ) {
                if ( !exists $ROWDATA{'email'} && exists $ROWDATA{'domain'} ) {
                    $ROWDATA{'email'} = $ROWDATA{'domain'};
                    delete $ROWDATA{'domain'};
                }
                if ( !$ROWDATA{'password'} ) {
                    $ROWDATA{'password'} = Cpanel::PasswdStrength::Generate::generate_password(12);
                }
                $ROWDATA{'quota'} = int $ROWDATA{'quota'} || 'unlimited';
            }

            foreach my $key ( 'source', 'target', 'email' ) {
                if ( exists $ROWDATA{$key} ) {
                    if ( $key eq 'target' && $ROWDATA{$key} =~ m/\@/ ) {
                        $ROWDATA{$key} = Cpanel::Validate::EmailRFC::scrub( $ROWDATA{$key} );
                        next;
                    }
                    $ROWDATA{$key} = _force_address(
                        $ROWDATA{$key},
                        {
                            'domain'        => $ROWDATA{'domain'},
                            'defaultdomain' => $OPTS{'defaultdomain'},
                            'mydomains_ref' => \%MYDOMAINS,
                        }
                    );
                }
            }
            push @ROWS, \%ROWDATA;
        }

    }
    Storable::lock_nstore( \@ROWS, $csvdatafile . '.import' );
    return [ 'rows' => scalar @ROWS ];
}

sub api2_fetchimportdata {
    my $importdata = eval { Cpanel::SafeStorable::lock_retrieve( $csvdatafile . '.import' ) };

    if ($@) {
        $Cpanel::CPERROR{$Cpanel::context} = "Could not fetch import data.";
        return;
    }

    return $importdata;
}

sub api2_uploadimport {

    my $randdata = Cpanel::Rand::Get::getranddata(32);
    $Cpanel::CPVAR{'csvimportid'} = $randdata;
    Cpanel::SafeDir::MK::safemkdir( $Cpanel::homedir . '/tmp/cpcsvimport', '0700' );
    my @RSD;
    local $Cpanel::IxHash::Modify = 'none';
  FILE:
    foreach my $file ( keys %Cpanel::FORM ) {
        next FILE if $file =~ m/^file-(.*)-key$/;
        next FILE if $file !~ m/^file-(.*)/;
        my $tmpfilepath = $Cpanel::FORM{$file};
        rename( $tmpfilepath, $Cpanel::homedir . '/tmp/cpcsvimport/' . $randdata );
        push @RSD, { 'id' => $randdata };
        last;
    }
    return \@RSD;
}

sub _force_address {
    my $email   = shift;
    my $opt_ref = shift;

    if ( !exists $opt_ref->{'mydomains_ref'} ) {
        my %MYDOMAINS = map { $_ => 1 } @Cpanel::DOMAINS;
        $opt_ref->{'mydomains_ref'} = \%MYDOMAINS;
    }

    if ( $email =~ tr/\@// ) {
        my ( $user, $domain ) = split( /\@/, $email, 2 );
        if ( !exists $opt_ref->{'mydomains_ref'}->{$domain} ) {
            $email = $user;
        }
    }
    if ( !( $email =~ tr/\@// ) ) {
        if ( $opt_ref->{'domain'} && exists $opt_ref->{'mydomains_ref'}->{ $opt_ref->{'domain'} } ) {
            $email .= '@' . $opt_ref->{'domain'};
        }
        elsif ( $opt_ref->{'defaultdomain'} && exists $opt_ref->{'mydomains_ref'}->{ $opt_ref->{'defaultdomain'} } ) {
            $email .= '@' . $opt_ref->{'defaultdomain'};
        }
        else {
            $email .= '@' . $Cpanel::CPDATA{'DNS'};
        }
    }
    my ( $user, $domain ) = split( /\@/, lc $email );

    # Instead of scrubbing, we should be marking as invalid somehow and allowing the user to correct it.
    $user = Cpanel::Email::Normalize::EmailLocalPart::scrub($user);
    return $user . '@' . $domain;
}

my $csvimport_feature = { needs_feature => "csvimport" };
my $allow_demo        = { allow_demo    => 1 };

our %API = (
    uploadimport    => $csvimport_feature,
    processdata     => $csvimport_feature,
    fetchimportdata => $allow_demo,
    loaddata        => $allow_demo,
    columnchoices   => $allow_demo,
    data            => $allow_demo,
    configimport    => $allow_demo,
);

sub api2 {
    my ($func) = @_;
    return $API{$func} && { worker_node_type => 'Mail', %{ $API{$func} } };
    return;
}

1;
