package Cpanel::ApacheConf::ModRewrite::RewriteCond;

# cpanel - Cpanel/ApacheConf/ModRewrite/RewriteCond.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Cpanel::ApacheConf::ModRewrite::RewriteCond

=head1 SYNOPSIS

    #Note that “expr”-type RewriteCond directives are not supported.
    my $cond = Cpanel::ApacheConf::ModRewrite::RewriteCond->new_from_string(
        'RewriteCond %{HTTP_HOST} ^pattern [nocase]',
    );

    #Leading/trailing quotes will not be part of these functions’ returns.
    $cond->CondPattern();               #includes leading !, if present
    $cond->TestString();

    $cond->ornext();                    #returns 0 or 1

    $cond->pattern_matches('pattern');  #returns 1
    $cond->pattern_matches('dunno');    #returns 0

=head1 DESCRIPTION

A parser module for Apache mod_rewrite’s C<RewriteCond> directive
with pattern-matching logic. The pattern matching is able to handle
regular expressions as well as string and numeric comparison, but
cannot handle all types of patterns.

=cut

use strict;
use warnings;

use parent qw(
  Cpanel::ApacheConf::ModRewrite::DirectiveHasArgs
);

use Try::Tiny;

use Cpanel::ApacheConf::ModRewrite::Utils              ();
use Cpanel::ApacheConf::ModRewrite::RewriteCond::Utils ();
use Cpanel::Exception                                  ();

use constant {
    DIRECTIVE_NAME => 'RewriteCond',
};

sub new_from_string {
    my ( $class, @args ) = @_;

    my $self = $class->SUPER::new_from_string(@args);

    if ( ( $self->{'_TestString'} =~ tr<A-Z><a-z>r ) eq 'expr' ) {
        die Cpanel::Exception::create( 'Unsupported', "“[_1]” cannot parse “[_2]” expressions.", [ ref($self), 'ap_expr' ] );
    }

    return $self;
}

sub _args_to_self_parts {
    my ( $class, @args ) = @_;

    return (
        _TestString  => $args[0],
        _CondPattern => $args[1],
        _flags       => [ Cpanel::ApacheConf::ModRewrite::Utils::split_flags( $args[2] ) ],
    );
}

sub _stringify_args {
    my ($self) = @_;

    return map { $self->{$_} } qw( _TestString _CondPattern );
}

sub TestString {
    my ($self) = @_;

    return $self->{'_TestString'};
}

sub CondPattern {
    my ($self) = @_;

    return $self->{'_CondPattern'};
}

sub ornext {
    my ($self) = @_;

    return $self->has_flag('ornext');
}

sub pattern_matches {
    my ( $self, $test_value ) = @_;

    return Cpanel::ApacheConf::ModRewrite::RewriteCond::Utils::pattern_matches(
        $self->{'_CondPattern'},
        $test_value,
        ( $self->has_flag('nocase') ? 'nocase' : () ),
    );
}

1;
