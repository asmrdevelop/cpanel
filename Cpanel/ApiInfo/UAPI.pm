package Cpanel::ApiInfo::UAPI;

# cpanel - Cpanel/ApiInfo/UAPI.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
## no critic qw(TestingAndDebugging::RequireUseWarnings)
#
use base qw(Cpanel::ApiInfo::Modular);

use Cpanel::ConfigFiles ();

sub MODULES_DIR { return "$Cpanel::ConfigFiles::CPANEL_ROOT/Cpanel/API" }

sub SPEC_FILE_BASE { return 'cpanel_uapi' }

#
# Traverses all the UAPI modules in MODULES_DIR
# and looks for functions.
#
# Returns an arrayref of funcitons in the UAPI
# module
#
# This is typically called from Cpanel::ApiInfo::Modular::_update_transaction
# and runs are 'nobody' in a separate process so there is no concern about
# polluting the namespace in the parent process.
#
sub find_subs_in_path_ar {
    my ( $self, $path ) = @_;

    $path =~ m{/([^/]+)\.pm\z};
    my $module = $1;

    delete $INC{"Cpanel/API/$module.pm"};

    my $perl_code_sr = $self->_load_module_text_sr( $module, $path );
    return if !$perl_code_sr;

    local $@;

    my $loaded = eval { $self->_load_module( $module, $path ) };

    my $subs_ar;

    if ($loaded) {
        $path =~ m{/([^/]+)\.pm\z};
        my $module = $1;

        $subs_ar = find_calls_in_module($module);
    }

    # warn if $@ has been capture by the eval{} above
    warn "Error loading UAPI module in “$path”: $@" if $@ && $@ !~ m{Can't locate};

    require Class::Unload;
    Class::Unload->unload("Cpanel::API::${module}");

    return $subs_ar // [];
}

sub find_calls_in_module {
    my ($module) = @_;

    my %to_ignore = map { $_ => 1 } qw/apache_paths_facade lh locale logger carp croak try catch finally/;

    my $namespace = $Cpanel::API::{"${module}::"};

    local $@;    # Prevent trapped errors from propagating upwards
    my @subs = grep {
        !m{\A_} && !$to_ignore{$_} && eval { *{ $namespace->{$_} }{'CODE'} }
    } keys %$namespace;

    return \@subs;
}

1;
