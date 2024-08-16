package Cpanel::ApacheConf::ModRewrite::RewriteRule;

# cpanel - Cpanel/ApacheConf/ModRewrite/RewriteRule.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Cpanel::ApacheConf::ModRewrite::RewriteRule

=head1 SYNOPSIS

    my $cond = Cpanel::ApacheConf::ModRewrite::RewriteRule->new_from_string(
        'RewriteRule ^pattern http://else/where [NC]',
    );

    #Leading/trailing quotes will not be part of these functions’ returns.
    $cond->Pattern();               #includes leading !, if present
    $cond->Substitution();

    $cond->pattern_matches('pattern');  #returns 1
    $cond->pattern_matches('dunno');    #returns 0

=head1 DESCRIPTION

A parser module for Apache mod_rewrite’s C<RewriteRule> directive.

=cut

use strict;
use warnings;

use parent qw(
  Cpanel::ApacheConf::ModRewrite::DirectiveHasArgs
);

use Cpanel::ApacheConf::ModRewrite::Utils ();

use constant {
    DIRECTIVE_NAME => 'RewriteRule',
};

sub new {
    my ( $class, $pattern, $substitution, %flags ) = @_;

    my $self = {
        _Pattern      => $pattern,
        _Substitution => $substitution,
        _flags        => [

            #TODO: Update this logic to be “neater”.
            ( map { defined $flags{$_} ? "$_=$flags{$_}" : $_ } keys %flags ),
        ],
    };

    return bless $self, $class;
}

sub _args_to_self_parts {
    my ( $class, @args ) = @_;

    return (
        _Pattern      => $args[0],
        _Substitution => $args[1],
        _flags        => [ Cpanel::ApacheConf::ModRewrite::Utils::split_flags( $args[2] ) ],
    );
}

sub _stringify_args {
    my ($self) = @_;

    return map { $self->{$_} } qw( _Pattern _Substitution );
}

sub Substitution {
    my ($self) = @_;

    return $self->{'_Substitution'};
}

sub Pattern {
    my ($self) = @_;

    return $self->{'_Pattern'};
}

sub pattern_matches {
    my ( $self, $test_value ) = @_;

    if ( !defined $test_value ) {
        die "Missing test value ($self)!";
    }

    my $pattern = $self->{'_Pattern'};

    my ($negated) = ( $pattern =~ s<\A(!)><> );

    my $ret = Cpanel::ApacheConf::ModRewrite::Utils::regexp_str_match(
        $pattern,
        $test_value,
        ( $self->has_flag('nocase') ? 'nocase' : () ),
    );

    $ret = !$ret if $negated;

    return $ret ? 1 : 0;
}

1;
