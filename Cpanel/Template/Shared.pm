package Cpanel::Template::Shared;

# cpanel - Cpanel/Template/Shared.pm                 Copyright 2022 cPanel L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::LoadFile::ReadFast ();

=encoding utf-8

=head1 NAME

Cpanel::Template::Shared - Template functions shared between Cpanel::Template and Cpanel::Template::Unauthenticated

=head1 SYNOPSIS

    use Cpanel::Template::Shared;

    *Template::Provider::_template_content    = *Cpanel::Template::Shared::_template_content;
    *Template::Provider::_load_compiled       = *Cpanel::Template::Shared::_load_compiled;
    *Template::Provider::_compiled_is_current = *Cpanel::Template::Shared::_compiled_is_current;

=head1 DESCRIPTION

This module is used to override Template Toolkits internals in order to avoid
PerlIO slowdowns and provide additional compiled template sanity checking.

=cut

sub _template_content {
    my ( $self, $path ) = @_;

    return ( undef, "No path specified" ) if !$path;

    if ( open my $fh, '<:stdio', $path ) {
        my $data = '';
        Cpanel::LoadFile::ReadFast::read_all_fast( $fh, $data );
        if ( !$! ) {
            if ( my $mtime = ( stat($fh) )[9] ) {
                if ( close $fh ) {
                    return ( $data, undef, $mtime );
                }
            }
        }
    }

    return ( undef, "$path: $!", undef );
}

sub _load_compiled {
    my ( $self, $path ) = @_;

    if ( open my $fh, '<:stdio', $path ) {
        my $data = '';
        eval { Cpanel::LoadFile::ReadFast::read_all_fast( $fh, $data ); };
        if ($@) {
            return $self->error("Failed to load compiled template: $path: $@");
        }

        my $tt_doc;
        {
            no warnings;             ## no critic qw(TestingAndDebugging::ProhibitNoWarnings) -- avoid Use of uninitialized value in concatenation (.) or string at (eval 18)[/usr/local/cpanel/Cpanel/Template/Shared.pm:62] line 47.
            $tt_doc = eval $data;    ## no critic qw(BuiltinFunctions::ProhibitStringyEval)
        }
        if ($@) {
            return $self->error("Failed to load compiled template: $path: $@");
        }

        $INC{$path} = $path;         ## no critic qw(Variables::RequireLocalizedPunctuationVars) -- we are actually loaded the code here so local is NOT what we want

        # If all goes well $tt_doc is a Template::Document object
        return $tt_doc;
    }

    return $self->error("Failed to open compiled template: $path: $!");

}

sub _compiled_is_current {

    # The logic is the same as Template::Provider::_compiled_is_current except for the addition of a compiled size check to address CPANEL-27948
    my ( $self, $template_name, $uncompiled_template_mtime ) = @_;

    my $compiled_name = $self->_compiled_filename($template_name) || return 0;

    return 0 unless -r $compiled_name;

    my ( $compiled_size, $compiled_mtime ) = ( stat(_) )[ 7, 9 ];
    return 0 unless $compiled_size && $compiled_mtime;    # Size must be > 0

    my $template_mtime = $uncompiled_template_mtime || $self->_template_modified($template_name) || return;
    return $compiled_mtime == $template_mtime ? $template_mtime : 0;
}

1;
