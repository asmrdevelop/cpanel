package Cpanel::Update::Tiers;

# cpanel - Cpanel/Update/Tiers.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::JSON                         ();
use Cpanel::FileUtils::Write::JSON::Lazy ();
use Cpanel::Update::Config               ();
use Cpanel::Version::Full                ();
use Cpanel::Version::Compare             ();

use Scalar::Util ();

use constant TIERS_JSON_URI  => '/cpanelsync/TIERS.json';    # source for the TIERS.json file
use constant TIERS_JSON_FILE => '/etc/cpanel/TIERS.json';    # where to save the file

sub new ( $class, %args ) {

    my $self = {};
    $self->{'tiers_url'}  = $args{'tiers_url'}  || TIERS_JSON_URI;
    $self->{'tiers_path'} = $args{'tiers_path'} || TIERS_JSON_FILE;

    # During fresh installs, we don't want the TIERS.json file to change once we initially download it.
    # Do we set the cache expiration time to 6 hours.
    $self->{'cache_expiration_time'} = $args{'cache_expiration_time'} || $ENV{'CPANEL_BASE_INSTALL'} ? 6 * 3600 : 300;

    # Optional logger.
    $self->{'logger'} = $args{'logger'} if $args{'logger'};

    return bless $self, $class;
}

##################################################################################
# logger (method)
##################################################################################
# Returns the logger object attached to this object.
# If one does not exist, it is created.
# If {'logger'} is set to a scalar (like 'disabled'), it makes a quiet logger
# object that doesn't log anything.
##################################################################################

sub logger ($self) {

    require Cpanel::Logger;
    $self->{'logger'} ||= Cpanel::Logger->new();

    # Setting the log file to /dev/null is subtantially easier than trying to overload methods:
    if ( !Scalar::Util::blessed( $self->{'logger'} ) ) {
        $self->{'logger'} = Cpanel::Logger->new(
            {
                'alternate_logfile' => '/dev/null',
            }
        );
    }

    return $self->{'logger'};
}

##################################################################################
# sync_tiers_file( %args )
##################################################################################
# Downloads the current TIERS.json file from the httpupdate mirrors and saves it to $self->{'tiers_path'}
# Returns 1 for success and 0 for failure
# Normally called without any args.
##################################################################################

sub sync_tiers_file ($self) {

    require Cpanel::Config::Sources;
    my $remote_tiers_host = Cpanel::Config::Sources::loadcpsources()->{'HTTPUPDATE'};

    my $tiers_json;
    {
        require Cpanel::Alarm;
        require Cpanel::HttpRequest;
        my $alarm = Cpanel::Alarm->new( 45, sub { die 'Timeout while fetching version information.' } );
        $tiers_json = Cpanel::HttpRequest->new(
            'logger'     => ( Scalar::Util::blessed( $self->logger() ) ? $self->logger() : undef ),    # undef restores the legacy behavior
            'hideOutput' => 1,
            'die_on_404' => 1,
            'retry_dns'  => 0,
        )->request(
            'host'   => $remote_tiers_host,
            'url'    => $self->{'tiers_url'},
            'signed' => 1,
        );
    }

    if ( !$tiers_json ) {
        die( "Error downloading ${remote_tiers_host}" . TIERS_JSON_URI );
    }

    my $json_hr = Cpanel::JSON::Load($tiers_json) or die( "Could not load ${remote_tiers_host}" . TIERS_JSON_URI . ": $@" );

    if ( !-e $self->{'tiers_path'} ) {
        require File::Basename;
        my ( $basename, $dirname, $suffix ) = File::Basename::fileparse( $self->{'tiers_path'} );

        if ( !-e $dirname ) {
            require Cpanel::SafeDir::MK;
            Cpanel::SafeDir::MK::safemkdir( $dirname, 0755 );
        }
    }
    return 0 unless Cpanel::FileUtils::Write::JSON::Lazy::write_file( $self->{'tiers_path'}, $json_hr, 0644 );

    return 1;
}

##################################################################################
# tiers_hash( %args )
##################################################################################
# Will load the TIERS.json file and return a hash of it's contents.
# This if the file is too old (older than 1 hour by default) it will download a fresh copy
# Normally called without any args
##################################################################################

sub tiers_hash ($self) {

    return $self->{'tiers_hash'} if exists $self->{'tiers_hash'};

    eval {
        if ( $self->tiers_cache_expired() ) {
            $self->sync_tiers_file();
        }
    };
    if ($@) {
        my $error = 'Tried to sync version ' . $self->{'tiers_path'} . ' file but failed: ' . $@;
        if ( $self->logger->can('error') ) {
            $self->logger->error($error);
        }
        else {
            $self->logger->warn($error);
        }
        return;
    }

    $self->{'tiers_hash'} = Cpanel::JSON::SafeLoadFile( $self->{'tiers_path'} );
    return $self->{'tiers_hash'};
}

##################################################################################
# tiers_cache_expired( )
##################################################################################
# Checks to see if the TIERS.json is too old to be considered "current" or not.
# Returns 1 if it is too old or 0 if it is recent. $default_expiration_time is 3 minutes.
# Called without any args
##################################################################################

sub tiers_cache_expired ($self) {

    if ( !-e $self->{'tiers_path'} || -z _ || ( ( stat(_) )[9] + $self->{'cache_expiration_time'} ) < time ) {
        return 1;
    }
    else {
        return 0;
    }
}

##################################################################################
# get_current_lts_expiration_status();
##################################################################################
# Gathers and returns information on current status of tier and if it is expiring soon.
##################################################################################

sub get_current_lts_expiration_status ($self) {
    my %results;

    $results{'full_version'} = Cpanel::Version::Full::getversion();
    $results{'expiration'}   = $self->get_expires_for_version( $results{'full_version'} );

    return unless defined $results{'expiration'};

    $results{'expires_in_next_three_months'} = 0;
    my $time = time;

    my $time_three_months_from_now = $time + 3600 * 24 * 90;

    if ( $results{'expiration'} && ($time_three_months_from_now) > $results{'expiration'} ) {
        $results{'expires_in_next_three_months'} = 1;
    }

    return \%results;
}

sub get_build_info ( $self, $version ) {

    return $self->_visit_major_builds_from_version(
        $version,
        sub {
            my ($build) = @_;

            # we found a build that match
            return $build if $build && defined $build->{'build'} && $build->{'build'} eq $version;
            return;
        }
    );
}

sub _visit_major_builds_from_version ( $self, $version, $visit ) {

    my ($major) = $version =~ m/^11\.([0-9]+)\.[0-9]+\.[0-9]+$/;
    $major or return;        # Not a valid version. Obviously not stable :)
    $major += $major % 2;    #Make it even.
    $major = "11.$major";

    my $tiers_hr    = $self->tiers_hash()            or return;
    my $major_array = $tiers_hr->{'tiers'}->{$major} or return;

    # just in case this is getting called on a machine without a TIERS.json
    return unless ref $major_array eq 'ARRAY';

    foreach my $build (@$major_array) {
        my $got = $visit->($build);
        return $got if $got;
    }

    return;
}

sub get_expires_for_version ( $self, $version = undef ) {
    return unless defined $version;

    # first check if the build provides its own information
    my $build_info = $self->get_build_info($version) or return;
    return $build_info->{'expires'} if defined $build_info->{'expires'};

    # then fallback to the first LTS providing EOL for this major versoon
    # Note: the TIERS.json has a design issue, the expire should be set at the main level
    #   and note on the LTS only

    # return EOL from the first LTS build which has one exires set
    return $self->_visit_major_builds_from_version(
        $version,
        sub {
            my ($build) = @_;
            return unless $build;
            if ( $build->{is_lts} && defined $build->{expires} ) {
                return $build->{expires};
            }
            return;
        }
    );
}

sub get_current_tier ($self) {

    return $self->{'current_update_tier'} if $self->{'current_update_tier'};

    my $tier = Cpanel::Update::Config::load()->{'CPANEL'};

    # Permit customers to put CPANEL=76 in their cpupdate.conf file.
    if ( $tier =~ m{^[0-9]+$} ) {
        $tier = '11.' . $tier;
    }

    return $self->{'current_update_tier'} = $tier;
}

sub is_explicit_version ( $self, $tier = undef ) {

    return unless defined $tier && length $tier;

    # If the tier is set explicitly to the version, then the version is the tier.
    # 11.72.0.2
    return ( $tier =~ m/^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ ) ? 1 : 0;
}

# NOTE: This method does not validate the value of 'build' in the JSON tree.

sub get_remote_version_for_tier ( $self, $tier = undef ) {

    return unless defined $tier && length $tier;

    return $tier if $self->is_explicit_version($tier);

    my $tiers_hash = $self->tiers_hash;

    # Major version tier.
    # CPANEL=11.72
    if ( $tier =~ m/^([0-9]+\.[0-9]+)$/ ) {
        my $LTS = "$1";    # Be sure to stringify it.

        ref $tiers_hash->{'tiers'} eq 'HASH' or return;
        my $major_versions = $tiers_hash->{'tiers'}->{$LTS};

        ref $major_versions eq 'ARRAY' or return;
        foreach my $build (@$major_versions) {
            next unless $build->{'is_main'};

            return $build->{'build'};
        }

        return;            # Couldn't find an is_main inside $LTS
    }

    #
    # CPANEL=11.68.9999
    #
    # Try to find it in the branches section and if not fall through to named tiers.
    # This code is primarily for development branch purposes.

    if ( $tier =~ m/^([0-9]+\.[0-9]+\.[0-9]+)$/ ) {
        my $dev_branch = "$1";    # Be sure to stringify it.
        if ( ref $tiers_hash->{'branch'} eq 'HASH' ) {
            my $build = $tiers_hash->{'branch'}->{$dev_branch};
            if ( $build && ref $build eq 'ARRAY' ) {
                if ( $build->[0] && ref $build->[0] eq 'HASH' ) {
                    return $build->[0]->{'build'};
                }
            }
        }
    }

    # The tier is assumed to be named here.
    # We have to walk the entire tree to find it.
    ref $tiers_hash->{'tiers'} eq 'HASH' or return;
    foreach my $versions_in_major ( values %{ $tiers_hash->{'tiers'} } ) {
        ref $versions_in_major eq 'ARRAY' or next;
        foreach my $release (@$versions_in_major) {
            ref $release eq 'HASH' or next;

            $release->{'named'} or next;

            ref $release->{'named'} eq 'ARRAY' or next;
            foreach my $name ( @{ $release->{'named'} } ) {

                # Found the tier in the JSON tree!
                # Cache the result.
                return $release->{'build'} if $name eq $tier;
            }
        }
    }

    return;
}

sub get_main_for_version ( $self, $current_version = undef ) {

    $current_version                                      or return;
    $current_version =~ m{^11\.([0-9]+)\.[0-9]+\.[0-9]+$} or return;

    my $major_version = $1;
    $major_version++ if ( $major_version % 2 );    # Make it even if it's odd.

    my $tiers_hash = $self->tiers_hash;
    ref $tiers_hash->{'tiers'} eq 'HASH' or return;

    my $build_list = $tiers_hash->{'tiers'}->{"11.$major_version"} or return;
    ref $build_list eq 'ARRAY'                                     or return;

    foreach my $build (@$build_list) {
        next unless $build->{'is_main'};
        return $build->{'build'};    # We found the is_main for 11.76.0.4 (or whatver)
    }

    return;                          #If there's no LTS forwad of #
}

sub get_lts_for ( $self, $current_version = undef, $next = undef ) {

    $current_version                             or return;
    $current_version =~ m{^11\.(\d+)\.\d+\.\d+$} or return;

    my $major_version = $1;
    $major_version++ if ( $major_version % 2 );    # Make it even if it's odd.

    $major_version += 2 if ($next);                # Find the next LTS , not the current one

    my $tiers_hash = $self->tiers_hash;
    ref $tiers_hash->{'tiers'} eq 'HASH' or return;

    # Walk forward each major step (up to 10) to find an is_lts.
    foreach my $step ( 0 .. 50 ) {
        my $forward_major = sprintf( "11.%02d", $major_version + $step * 2 );

        my $major_versions = $tiers_hash->{'tiers'}->{$forward_major} or next;

        ref $major_versions eq 'ARRAY' or next;
        foreach my $build (@$major_versions) {
            next unless $build->{'is_lts'};
            return $build->{'build'};
        }
    }

    return;    #If there's no LTS forwad of #
}

sub get_update_availability ($self) {

    my $current_tier    = $self->get_current_tier();
    my $current_version = Cpanel::Version::Full::getversion();

    # version compare and complain
    my $newest_version = $self->get_remote_version_for_tier($current_tier);

    # Strip 11. off of all versions for the API calls.
    $current_version =~ s{^11\.}{};
    $newest_version  =~ s{^11\.}{} if defined $newest_version;

    return {
        'tier'             => $current_tier,
        'current_version'  => $current_version,
        'newest_version'   => $newest_version,
        'update_available' => Cpanel::Version::Compare::compare( $newest_version, '>', $current_version ) ? 1 : 0,
    };
}

sub is_slow_rollout_tier ( $self, $version = undef ) {

    $version or return;

    my $tiers_hr = $self->tiers_hash;
    ref $tiers_hr->{'tiers'} eq 'HASH' or return;

    my $build = $self->get_build_info($version) or return;

    return unless $build->{'named'};
    return if ref $build->{'named'} ne 'ARRAY';

    foreach my $tier ( @{ $build->{'named'} } ) {
        next unless $tier;
        return 1 if lc($tier) eq 'release';
    }

    return;
}

# Convert TIERS.json to the flattened legacy hash we used to have.
# i.e.
#
# my $tiers = {
#    '11.30' => "11.30.1.8",
#    current => '11.72.0.1',
#    ...
#}
sub get_flattened_hash ($self) {

    my %tiers;

    my $tiers_hr = $self->tiers_hash;
    ref $tiers_hr->{'tiers'} eq 'HASH' or return;
    foreach my $major ( keys %{ $tiers_hr->{'tiers'} } ) {
        my $versions_in_major = $tiers_hr->{'tiers'}->{$major};
        ref $versions_in_major eq 'ARRAY' or next;
        foreach my $release (@$versions_in_major) {
            ref $release eq 'HASH' or next;

            if ( $release->{'is_main'} ) {
                $tiers{"$major"} = $release->{'build'};
            }

            $release->{'named'} or next;

            ref $release->{'named'} eq 'ARRAY' or next;
            foreach my $name ( @{ $release->{'named'} } ) {
                $tiers{$name} = $release->{'build'};
            }
        }
    }

    return \%tiers;
}

1;
