package Cpanel::Exception::Template;

# cpanel - Cpanel/Exception/Template.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw( Cpanel::Exception );

use Cpanel::ScalarUtil   ();
use Cpanel::LocaleString ();

#Named parameters:
#   - error             required, a Template::Exception instance
#   - template_path     optional, the template's filesystem path
#
sub _default_phrase {
    my ($self) = @_;

    my $err = $self->get('error');

    if ( !UNIVERSAL::isa( $err, 'Template::Exception' ) ) {
        die "Error must be a Template::Exception instance, not “$err”!";
    }

    my $path = $self->get('template_path');

    if ($path) {
        my ( $type, $info ) = $self->_find_deepest_type_and_info($err);
        return Cpanel::LocaleString->new(
            '[asis,Template Toolkit] encountered an error of type “[_1]” while parsing the template “[_2]”: [_3]',
            $type,
            $path,
            $info,
        );
    }

    return Cpanel::LocaleString->new(
        '[asis,Template Toolkit] encountered an error of type “[_1]”: [_2]',
        $self->_find_deepest_type_and_info($err),
    );
}

#TT nests exceptions within each other like so:
#
#bless( [
#    'file',
#    bless( [
#            'parse',
#            'input text line 167-180: unexpected end of input',
#            undef
#        ], 'Template::Exception' ),
#    undef
#], 'Template::Exception' );
#
#The "outer" exceptions are much less useful to us than the
#"inner" exceptions, so let's just extract what we need.
#
sub _find_deepest_type_and_info {
    my ( $self, $tt_err ) = @_;

    # Note: the error may be a Specio::Constraint error so we now
    # look to see if info is going to cause another exception

    while ( $tt_err->can('info') && Cpanel::ScalarUtil::blessed( $tt_err->info() ) ) {
        $tt_err = $tt_err->info();
    }

    return ( $tt_err->type(), $tt_err->can('info') ? $tt_err->info() : $tt_err->can('message') ? $tt_err->message() : $tt_err->can('description') ? $tt_err->description() : 'unknown' );
}

1;
