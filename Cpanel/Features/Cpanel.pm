package Cpanel::Features::Cpanel;

# cpanel - Cpanel/Features/Cpanel.pm                 Copyright 2022 cPanel L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use Cpanel::ConfigFiles                  ();
use Cpanel::StringFunc::Case             ();
use Cpanel::Features::Load               ();
use Cpanel::AdminBin::Serializer::FailOK ();
use Cpanel::FileUtils::Write::JSON::Lazy ();
use Cpanel::LoadModule                   ();

my %FEATURE_MEMORY_CACHE;
my %FEATURE_FILE_LIST_MEMORY_CACHE;

sub fetch_feature_file_list_from_featurelist {
    my ($featurelist) = @_;
    return [
        $featurelist
        ? (
            { 'file' => 'default',    'logic' => 'disabler' },
            { 'file' => $featurelist, 'logic' => 'accept', 'skip_names' => [ 'disabled', 'default' ] },
            { 'file' => 'disabled',   'logic' => 'disabler' }
          )
        : (
            { 'file' => 'default',  'logic' => 'disabler' },
            { 'file' => 'disabled', 'logic' => 'disabler' }
        )
    ];

}

sub fetch_feature_file_list {
    my $cpuser_ref = $_[0];
    return fetch_feature_file_list_from_featurelist( $cpuser_ref->{'FEATURELIST'} );
}

# this allow to freeze time ( for test for example )
my $_now;

sub now {
    my $value = shift;
    if ( defined $value ) {
        if ( $value eq 'freeze' ) {
            $_now = time();
        }
        elsif ( $value eq 'unfreeze' ) {
            $_now = undef;
        }
        else {
            $_now = $value;
        }
    }

    return $_now || scalar time();
}

sub calculate_cache_file_name_and_maxmtime {    ##no critic qw(RequireArgUnpacking)
    my @FEATURE_FILES     = @{ $_[0] };
    my $max_feature_mtime = my $max_team_feature_mtime = 0;
    my ( $now, @feature_cache_name );

    for ( 0 .. $#FEATURE_FILES ) {
        my $file = $FEATURE_FILES[$_]->{'file'};
        next if ( $FEATURE_FILES[$_]->{'skip_names'} && ref $FEATURE_FILES[$_]->{'skip_names'} eq 'ARRAY' && grep { $_ eq $file } @{ $FEATURE_FILES[$_]->{'skip_names'} } );
        my $filename = Cpanel::Features::Load::featurelist_file($file);
        $FEATURE_FILES[$_]->{'mtime'} = ( stat($filename) )[9];
        if ( $FEATURE_FILES[$_]->{'mtime'} ) {
            $max_feature_mtime = $FEATURE_FILES[$_]->{'mtime'} if ( $max_feature_mtime < $FEATURE_FILES[$_]->{'mtime'} && $FEATURE_FILES[$_]->{'mtime'} < ( $now ||= now() ) );
            push @feature_cache_name, $file;
        }
    }
    my $team_info = '';
    if ( $ENV{'TEAM_USER'} ) {
        Cpanel::LoadModule::load_perl_module('Cpanel::Team::Features');    # hide it from updatenow.static
        $max_team_feature_mtime = Cpanel::Team::Features::get_max_team_feature_mtime( $ENV{'TEAM_OWNER'}, $ENV{'TEAM_USER'} );
        $team_info              = "_$ENV{'TEAM_OWNER'}_$ENV{'TEAM_USER'}";
        $max_feature_mtime      = $max_feature_mtime > $max_team_feature_mtime ? $max_feature_mtime : $max_team_feature_mtime;
    }

    return ( "$Cpanel::ConfigFiles::features_cache_dir/featurelist-" . join( '_', @feature_cache_name ) . "$team_info.v2.cache", $max_feature_mtime );
}

sub populate {
    my ( $feature_files_ref, $data_ref, $cache_ref ) = @_;
    my ( $uc_feature_name, $FEATURES );
    foreach my $feature_list_ref ( @{$feature_files_ref} ) {
        my $cPanel_user_FEATURES = Cpanel::Features::Load::load_featurelist( $feature_list_ref->{'file'} );
        $FEATURES = $cPanel_user_FEATURES;
        if ( $ENV{'TEAM_USER'} ) {
            Cpanel::LoadModule::load_perl_module('Cpanel::Team::Features');    # hide it from updatenow.static
            $FEATURES = Cpanel::Team::Features::load_team_feature_list( $FEATURES, $feature_list_ref->{'file'} );
        }
        if ( $feature_list_ref->{'logic'} eq 'disabler' ) {
            foreach my $feature_name ( keys %$FEATURES ) {
                $uc_feature_name = 'FEATURE-' . Cpanel::StringFunc::Case::ToUpper($feature_name);
                if ( $FEATURES->{$feature_name} ne '1' && $FEATURES->{$feature_name} ne '' ) {
                    $cache_ref->{$uc_feature_name} = $data_ref->{$uc_feature_name} = $FEATURES->{$feature_name};
                }
            }
        }
        else {
            foreach my $feature_name ( keys %$FEATURES ) {
                $uc_feature_name = 'FEATURE-' . Cpanel::StringFunc::Case::ToUpper($feature_name);
                if ( $FEATURES->{$feature_name} eq '1' ) {
                    delete $data_ref->{$uc_feature_name};
                    delete $cache_ref->{$uc_feature_name};
                }
                else {
                    $cache_ref->{$uc_feature_name} = $data_ref->{$uc_feature_name} = $FEATURES->{$feature_name};
                }
            }
        }
    }
    return 1;
}

##
## *** DO NOT CALL THIS FUNCTION DIRECTLY ON A CPDATA HASHREF
## *** IT WILL BLOW AWAY FEATURE- KEYS THAT CONFLICT INSTEAD
## *** OF PREFERRING THE KEYS IN THE HASHREF IS IS AUGMENTING
##
##  Returns: the mtime of the feature cache
##
sub augment_hashref_with_features {
    my ( $featurelist, $hashref, $now ) = @_;

    $now         ||= time();
    $featurelist ||= '';       # It is possible to have an empty feature list
    my $featurelistkey = $ENV{'TEAM_USER'} ? "${featurelist}_$ENV{'TEAM_OWNER'}_$ENV{'TEAM_USER'}" : $featurelist;

    my ( $feature_cache_ref, $feature_cache_file, $max_feature_mtime, $feature_files_ref );

    if ( exists $FEATURE_FILE_LIST_MEMORY_CACHE{$featurelistkey} ) {
        ( $feature_files_ref, $feature_cache_file, $max_feature_mtime ) = @{ $FEATURE_FILE_LIST_MEMORY_CACHE{$featurelistkey} };
    }
    else {
        $feature_files_ref = fetch_feature_file_list_from_featurelist($featurelist);
        ( $feature_cache_file, $max_feature_mtime ) = calculate_cache_file_name_and_maxmtime($feature_files_ref);
        $FEATURE_FILE_LIST_MEMORY_CACHE{$featurelistkey} = [ $feature_files_ref, $feature_cache_file, $max_feature_mtime ];
    }

    if ( exists $FEATURE_MEMORY_CACHE{$feature_cache_file} ) {
        if ( $FEATURE_MEMORY_CACHE{$feature_cache_file}{'mtime'} == $max_feature_mtime ) {
            $feature_cache_ref = $FEATURE_MEMORY_CACHE{$feature_cache_file}{'cache'};
        }
    }

    Cpanel::AdminBin::Serializer::FailOK::LoadModule() if !$INC{'Cpanel/AdminBin/Serializer.pm'};
    if ( !$feature_cache_ref && $INC{'Cpanel/AdminBin/Serializer.pm'} ) {
        my $feature_cache_file_mtime = ( stat($feature_cache_file) )[9];
        Cpanel::LoadModule::load_perl_module('Cpanel::Team::Config');    # hide it from updatenow.static
        my $team_cache_file_mtime = Cpanel::Team::Config::get_mtime_team_config( $ENV{'TEAM_USER'}, $ENV{'TEAM_OWNER'} );
        if ( $feature_cache_file_mtime && $feature_cache_file_mtime > $max_feature_mtime && $feature_cache_file_mtime < $now && $feature_cache_file_mtime > $team_cache_file_mtime ) {
            $feature_cache_ref = Cpanel::AdminBin::Serializer::FailOK::LoadFile($feature_cache_file);
            if ( $feature_cache_ref && ref $feature_cache_ref eq 'HASH' ) {
                $FEATURE_MEMORY_CACHE{$feature_cache_file} = { 'mtime' => $max_feature_mtime, 'cache' => $feature_cache_ref };
            }
        }
    }

    if ( $feature_cache_ref && ref $feature_cache_ref eq 'HASH' ) {
        if (%$hashref) {
            foreach my $key ( keys %{$feature_cache_ref} ) {
                $hashref->{$key} = $feature_cache_ref->{$key};
            }
        }
        else {
            %$hashref = %$feature_cache_ref;
        }
        return $FEATURE_MEMORY_CACHE{$feature_cache_file}->{'mtime'};
    }

    my $cache_ref = {};
    populate( $feature_files_ref, $hashref, $cache_ref );

    $FEATURE_MEMORY_CACHE{$feature_cache_file} = { 'mtime' => $max_feature_mtime, 'cache' => $cache_ref };

    # Check $<
    # It's possible the caller has manually loaded this module in a root owned
    # process (albeit with AccessIds::ReducePrivileges):
    #  a call to featurewrap as root is bound to fail; it's also a security
    #  concern.
    if ( $INC{'Cpanel/JSON.pm'} && $cache_ref ) {
        if ( $> == 0 ) {
            if ( !-e $Cpanel::ConfigFiles::features_cache_dir ) {
                require Cpanel::SafeDir::MK;
                Cpanel::SafeDir::MK::safemkdir( $Cpanel::ConfigFiles::features_cache_dir, 0755 );
            }
            Cpanel::FileUtils::Write::JSON::Lazy::write_file( $feature_cache_file, $cache_ref, 0644 );
        }
        elsif ( !$INC{'Test/More.pm'} ) {

            # eval used to hide this from perlpkg and updatenow.static

            eval q{require Cpanel::AdminBin::Call};    ## no critic qw(BuiltinFunctions::ProhibitStringyEval)
            if ( $INC{'Cpanel/AdminBin/Call.pm'} ) {

                # If we already know the account is suspended then there’s
                # no point in sending the admin call.
                if ( !%Cpanel::CPDATA || !$Cpanel::CPDATA{'SUSPENDED'} ) {
                    warn if !eval { Cpanel::AdminBin::Call::call( 'Cpanel', 'feature', 'REBUILDFEATURECACHE' ); 1 };
                }
            }
            else {
                warn;
            }
        }
    }
    return $FEATURE_MEMORY_CACHE{$feature_cache_file}->{'mtime'};
}

sub clear_memory_cache {
    %FEATURE_MEMORY_CACHE           = ();
    %FEATURE_FILE_LIST_MEMORY_CACHE = ();
    return 1;
}

1;    # Magic true value required at end of module
__END__

=head1 NAME

Cpanel::Features::Cpanel - process feature list files

=head1 VERSION

This document describes Cpanel::Features::Cpanel version 0.0.3


=head1 SYNOPSIS

    use Cpanel::Features::Cpanel;

=head1 CONFIGURATION AND ENVIRONMENT

Cpanel::Features::Cpanel requires no configuration files or environment variables.

=head1 DEPENDENCIES

None.

=head1 INCOMPATIBILITIES

None reported.

=head1 BUGS AND LIMITATIONS

No bugs have been reported.

=head1 AUTHOR

J. Nick Koston  C<< nick@cpanel.net >>

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2011, cPanel, Inc. All rights reserved.


