package Cpanel::ApiInfo::Api2;

# cpanel - Cpanel/ApiInfo/Api2.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use base qw(Cpanel::ApiInfo::Modular);

use Cpanel::ConfigFiles ();

sub MODULES_DIR { return "$Cpanel::ConfigFiles::CPANEL_ROOT/Cpanel" }

sub SPEC_FILE_BASE { return 'cpanel_api2' }

#
# Traverses all the modules in MODULES_DIR
# and looks for api2 functions.
#
# Returns an arrayref of functions in the Api2
# module
#
# This is typically called from Cpanel::ApiInfo::Modular::_update_transaction
# and runs are 'nobody' in a separate process so there is no concern about
# polluting the namespace in the parent process.
#
sub find_subs_in_path_ar {
    my ( $self, $path ) = @_;

    return [] if $path =~ m/\/(?:Sync|Api2|Hulkd|TailWatch|ForkAsync).pm$/;    # These modules will never have any API2 calls

    my $ret = $self->_find_subs_in_path_ar($path);

    return $ret || [];
}

#NOTE: This runs as 'nobody'.
sub _find_subs_in_path_ar {
    my ( $self, $path ) = @_;

    require PPI;

    $path =~ m{/([^/]+)\.pm\z};
    my $module = $1;

    my $perl_code_sr = $self->_load_module_text_sr( $module, $path );
    return    if !$perl_code_sr;
    return [] if $$perl_code_sr !~ m/\n[\t ]*sub\s+api2/s;

    $self->_load_module( $module, $path ) or return;

    my $namespace      = $Cpanel::{"${module}::"};
    my $namespace_api2 = $namespace->{'api2'};
    return if !$namespace_api2;

    my $api2_cr = *{$namespace_api2}{'CODE'};
    return if !$api2_cr;

    my @words;
    my $api_hr;
    {
        no strict 'refs';
        $api_hr = \%{"Cpanel::${module}::API"};
    };
    if ( $api_hr && ref $api_hr eq 'HASH' ) {
        @words = keys %$api_hr;
    }
    if ( !@words ) {

        my $Document = PPI::Document->new($path);

        my ($objs_ar) = $Document->find(
            sub {
                $_[1]->isa('PPI::Token::Word') || $_[1]->isa('PPI::Token::Quote') ? 1 : 0;
            }
        ) || [];

        my @names = map { $_->isa('PPI::Token::Word') ? $_->content() : $_->string() } @$objs_ar;

        my %unique;
        @words = grep { !$unique{$_}++ } grep { $_ =~ m/^[A-Za-z][A-Za-z0-9_]*$/ } (@names);

    }

    local $SIG{'__DIE__'};

    my @api2_sub_names = sort grep {
        eval { $api2_cr->($_) }
    } @words;

    require Class::Unload;
    Class::Unload->unload("Cpanel::${module}");

    return \@api2_sub_names;
}

1;
