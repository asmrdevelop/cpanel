package Whostmgr::Mail::RBL;

# cpanel - Whostmgr/Mail/RBL.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use Cpanel::CachedDataStore ();
use Cpanel::DataStore       ();
use Cpanel::Logger          ();
use Cpanel::SafeDir::MK     ();
use Whostmgr::Template      ();

our $INFO_DIR      = '/var/cpanel/rbl_info';
our $ACLS_DIR      = '/usr/local/cpanel/etc/exim/acls/ACL_RBL_BLOCK';
our $TEMPLATES_DIR = '/usr/local/cpanel/etc/exim/templates';

my %DISTRBLS = (
    'spamcop' => {
        'dnslists' => ['bl.spamcop.net'],
        'url'      => 'http://spamcop.net/bl.shtml',
    },
    'spamhaus_spamcop' => {
        'dnslists' => [ 'zen.spamhaus.org', 'bl.spamcop.net' ],
        'url'      => undef,
    },
    'spamhaus' => {
        'dnslists' => ['zen.spamhaus.org'],
        'url'      => 'http://www.spamhaus.org/zen/index.lasso',
    },
);

my $logger = Cpanel::Logger->new();

sub add_rbl {
    my %OPTS = @_;

    if ( !$OPTS{'dnslists'} || !$OPTS{'rblname'} || !$OPTS{'rblurl'} ) {
        return ( 0, 'RBL name,RBL url, or dnslists missing' );
    }

    my $saferblname = $OPTS{'rblname'};
    $saferblname =~ s/[^\w\-\_]/_/g;

    if ( exists $DISTRBLS{$saferblname} ) {
        return ( 0, "The RBL name $saferblname is reserved" );
    }

    my @dnslists_split = split m{[\,\;\s\:]+}, $OPTS{'dnslists'};

    Cpanel::SafeDir::MK::safemkdir( $INFO_DIR, 0700 ) if !-d $INFO_DIR;

    Cpanel::DataStore::store_ref(
        "$INFO_DIR/${saferblname}.yaml",
        {
            'name'     => $OPTS{'rblname'},
            'dnslists' => \@dnslists_split,
            'url'      => $OPTS{'rblurl'},
        },
    );

    return ( 1, 'RBL def added' );
}

sub del_rbl {
    my %OPTS = @_;

    if ( !$OPTS{'rblname'} ) {
        return ( 0, 'RBL name missing' );
    }
    my $saferblname = $OPTS{'rblname'};
    $saferblname =~ s/[^\w\-\_]/_/g;

    if ( exists $DISTRBLS{$saferblname} ) {
        return ( 0, 'System RBLs cannot be removed' );
    }
    else {
        unlink "$ACLS_DIR/${saferblname}_rbl";
        unlink "$INFO_DIR/${saferblname}.yaml";

        return ( 1, 'RBL def removed' );
    }
}

sub list_rbls_from_yaml {
    my %rbls = %DISTRBLS;

    foreach my $dist_rbl_name ( keys %rbls ) {
        $rbls{$dist_rbl_name}->{'dist'} = 1;
    }

    if ( opendir my $dh, $INFO_DIR ) {
        while ( my $filename = readdir $dh ) {
            next if $filename !~ m{\.yaml\z};

            if ( my $rbl_info = Cpanel::CachedDataStore::fetch_ref("$INFO_DIR/$filename") ) {
                my $rbl_name = $rbl_info->{'name'};
                $rbl_info->{'dist'} = 0;
                $rbls{$rbl_name} = $rbl_info;
            }
        }

        closedir $dh;
    }

    return wantarray ? %rbls : \%rbls;
}

sub write_rbl_template {
    my ( $safe_rbl_name, @dnslists ) = @_;
    my $filename = "$ACLS_DIR/${safe_rbl_name}_rbl";

    if ( open my $fh, '>', $filename ) {
        print {$fh} Whostmgr::Template::process(
            {
                'file'     => $TEMPLATES_DIR . '/acls/ACL_RBL_BLOCK/rbl',
                'dnslists' => join( ' : ', @dnslists ),
            },
            1
        );
        close $fh;
        return 1;
    }
    else {
        $logger->warn("Failed to open RBL template file: $filename");
    }
    return;
}

sub write_all_rbl_templates {
    my $rbl_href = list_rbls_from_yaml();
    my @msgs;
    while ( my ( $name, $data ) = each %$rbl_href ) {
        if ( !write_rbl_template( $name, @{ $data->{'dnslists'} } ) ) {
            push @msgs, 'Failed to write RBL definition for ' . $name;
        }
    }
    return 1 if !scalar @msgs;
    return 0, join( ' ', @msgs );
}

1;
