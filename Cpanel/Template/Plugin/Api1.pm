package Cpanel::Template::Plugin::Api1;

# cpanel - Cpanel/Template/Plugin/Api1.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
## no critic qw(TestingAndDebugging::RequireUseWarnings) -- not yet safe here

use base 'Template::Plugin';

use Cpanel::FHTrap ();
use Cpanel::Debug  ();

our $MODE_CAPTURE = 0;
our $MODE_LIVE    = 1;

my $_Status;

sub new {
    my ($class) = @_;
    return bless {
        'live_exec' => \&_live_api1_exec,
        'exec'      => \&_captured_api1_exec,
        'pre_exec'  => \&_api1_pre_exec,
        'post_exec' => \&_api1_post_exec
    }, $class;
}

sub _api1_pre_exec {
    my ( $module, $func ) = @_;
    $Cpanel::IxHash::Modify = main::_get_ixhash_modify_method( $module, $func ) || 'safe_html_encode';
    return;
}

sub _api1_post_exec {
    $Cpanel::IxHash::Modify = 'safe_html_encode';
    return;
}

sub _live_api1_exec {
    return _api1_exec( $MODE_LIVE, @_ );
}

sub _captured_api1_exec {
    return _api1_exec( $MODE_CAPTURE, @_ );
}

sub _api1_exec {
    my ( $mode, $module, $func, $args ) = @_;
    if ( !$args ) {
        $args = $func;
        $func = undef;
    }

    my $argref;
    my $action = '';
    if ( ref $args eq 'HASH' ) {
        $action = join( ',', %{$args} );
        $argref = [ %{$args} ];
    }
    elsif ( ref $args eq 'ARRAY' ) {
        if ( grep { $_ == \%Cpanel::FORM } @{$args} ) {
            $action = '%FORM';
            $argref = [ \%Cpanel::FORM ];
        }
        else {
            $action = join( ',', @{$args} );
            $argref = $args;
        }
    }
    else {
        $action = $args;
        $argref = [$args];
    }

    main::load_api();    #init api1

    my $fhtrap;

    $fhtrap = Cpanel::FHTrap->new() if $mode == $MODE_CAPTURE;

    my $ix_modify_method = main::_get_ixhash_modify_method( $module, $func || $module );

    my $LCmodule = $module;
    $LCmodule =~ tr/[A-Z]/[a-z]/;

    if ( length $func ) {
        $action = $func . qq{(} . $action . qq{)};
    }

    eval { main::_api1( $module, $LCmodule, $action, ( $func || $module ), $argref, $ix_modify_method ); };

    if ($@) {
        Cpanel::Debug::log_warn("Execution error in Api1 call: $@");
    }

    return $fhtrap ? $fhtrap->close() : '';
}

sub status { return $_Status }

1;
