package Cpanel::Features::Load;

# cpanel - Cpanel/Features/Load.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Config::LoadConfig ();
use Cpanel::Team::Constants    ();

our $feature_list_dir;
our $feature_list_team_dir;

BEGIN {
    $feature_list_dir      = '/var/cpanel/features';
    $feature_list_team_dir = $Cpanel::Team::Constants::TEAM_FEATURES_DIR;
}

sub featurelist_file {
    die "“$_[0]” is not a valid feature name!" if ( -1 != index( $_[0], '/' ) && index( $_[0], $feature_list_team_dir ) != 0 );
    if ( index( $_[0], $feature_list_team_dir ) == 0 ) {
        return $_[0];
    }
    return "$feature_list_dir/$_[0]";
}

my ( $fl_hr, $err ) = @_;

# $_[0] = $name
# $_[1] = $delimiter
sub load_featurelist {
    $fl_hr = load_feature_file( $_[0], $_[1] );

    return wantarray ? %$fl_hr : $fl_hr if $fl_hr;

    # If we failed to get features beacuse the file is not readable, try with higher privileges.
    if ( load_and_fix_perms( $_[0] ) ) {

        # eval used to hide this from perlpkg and updatenow.static
        eval q{require Cpanel::AdminBin::Call};    ## no critic qw(BuiltinFunctions::ProhibitStringyEval)
        $fl_hr = Cpanel::AdminBin::Call::call( 'Cpanel', 'feature', 'LOADFEATUREFILE', $_[0], $_[1] );
        return wantarray ? %$fl_hr : $fl_hr if $fl_hr;
    }

    return;
}

sub is_feature_list {
    return ( !$_[0] || $_[0] eq '.' || $_[0] eq '..' || $_[0] =~ tr{\0\r\n}{} || !-e featurelist_file( $_[0] ) ) ? undef : 1;
}

sub load_and_fix_perms {
    return ( $> != 0 && !-r featurelist_file( $_[0] ) );
}

sub load_feature_file {
    ( $fl_hr, undef, undef, $err ) = Cpanel::Config::LoadConfig::loadConfig( featurelist_file( $_[0] ), undef, $_[1] || '[=:]', undef, qr/\s+/ );
    warn $err if $err;
    return $fl_hr;
}

1;    # Magic true value required at end of module
__END__

=head1 NAME

Cpanel::Features::Load - load the feature list

=head1 VERSION

This document describes Cpanel::Features::Load version 0.0.3


=head1 SYNOPSIS

    use Cpanel::Features::Load;

=head1 DESCRIPTION

The features in the WHM/Cpanel interface are controlled through a set of
files located in the F<whostmgr> directory under the installation directory.

As this information is needed in multiple places, this module hides the actual
implementation in terms of the files and directories involved. This allows
other code to depend on the interface without scattering file reading code
(and the hardcoded paths) throughout the codebase.

=head1 INTERFACE

The interface for this module can be partitioned into two groups: access to
the feature lists and access to features.

=head2 FEATURE LISTS

=head3 Cpanel::Features::featurelist_file( $name )

Returns the full pathname to the feature list named C<$name>. This method
breaks encapsulation with the rest of the module, but it allows for simpler
conversion of code from the old approach to the new one.

=head3 Cpanel::Features::load_featurelist( $name )

Returns a hash of the features for the feature list named C<$name>. The keys
of the hash are the features and the values are 1 for any enabled feature and
false otherwise.

=head1 DIAGNOSTICS

=over

=item C<< Unable to create feature dir '%s': %s >>

Possibly permission issues with parent directory.

=item C<< Unable to open feature dir '%s': %s >>

Possibly permission issues with the feature directory.

=item C<< Unable to load featurelist '%s': %s >>

Check file permissions.

=item C<< Unable to open '%s': %s >>

Check file permissions.

=item C<< Unable to read '%s': %s >>

Check permissions on the directory specified in the message.

=back


=head1 CONFIGURATION AND ENVIRONMENT

Cpanel::Features::Load requires no configuration files or environment variables.

=head1 DEPENDENCIES

None.

=head1 INCOMPATIBILITIES

None reported.

=head1 BUGS AND LIMITATIONS

No bugs have been reported.

=head1 AUTHOR

G. Wade Johnson  C<< wade@cpanel.net >>

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2009, cPanel, Inc. All rights reserved.
