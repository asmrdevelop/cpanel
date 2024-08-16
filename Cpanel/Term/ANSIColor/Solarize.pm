package Cpanel::Term::ANSIColor::Solarize;

# Copyright (c) 2015, cPanel, Inc.
# All rights reserved.
# http://cpanel.net
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
# 1. Redistributions of source code must retain the above copyright notice,
# this list of conditions and the following disclaimer.
#
# 2. Redistributions in binary form must reproduce the above copyright notice,
# this list of conditions and the following disclaimer in the documentation
# and/or other materials provided with the distribution.
#
# 3. Neither the name of the owner nor the names of its contributors may be
# used to endorse or promote products derived from this software without
# specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
# SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
# CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
# OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

#
# Copyright (c) 2011 Ethan Schoonover
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.
#

=pod

=encoding utf-8

=head1 NAME

Cpanel::Term::ANSIColor::Solarize - colored terminal output (maybe)

=head1 SYNOPSIS

    use Cpanel::Term::ANSIColor::Solarize ();

    #This might or might not apply ANSI coloring to the string “---”
    #before it gets printed, based on system conditions as described below.
    #
    print Cpanel::Term::ANSIColor::Solarize::colored( ["red on_grey3"], '---' );

=head1 CAVEAT

This module does too many things. It should B<always> colorize what it’s given;
the logic that detects the perl and STDOUT cases should be in a separate module
that calls into this one. We are committing this module as-is for 11.52 in the
interest of keeping the maintenance merge smaller.

=head1 DESCRIPTION

This module wraps C<Term::ANSIColor::colored()> with logic that aborts colorizing
and just returns the plain text if:

=over 4

=item * STDOUT is not a TTY. (The idea being that if STDOUT is not a TTY, then we are likely writing to a file.)

=item * The perl executable is not cPanel’s perl binary.

=back

NOTE: The above should be moved into a separate module as described in C<CAVEAT> above for 11.54.

In cases where C<colored()> does colorize the output, it applies the “Solarized” palette, using 256-color, 16-color, or 8-color versions as the terminal’s abilities allow.

=cut

use strict;
use warnings;

#NOTE: This module MUST be loadable from system perl because of how
#we do installs as of 11.52. That means no Try::Tiny, etc.

use Cpanel::Terminal   ();
use Cpanel::LoadModule ();

use constant ANSI_RESET => "\e[0m";

#Exposed for testing.
our $_cached_palette_ref;
our $_cached_max_colors;
our $_disable_init_once;    # allow testing to disable the behavior

my %_cached_colors;
my $_is_it_safe_to_colorize = undef;

sub _init_once {
    $_cached_palette_ref     = undef;
    $_cached_max_colors      = undef;
    %_cached_colors          = ();
    $_is_it_safe_to_colorize = undef;

    # On the outside chance that we ever somehow use this module in a BEGIN block,
    # we’ll need to reset these variables.

    if ( !$_disable_init_once && ${^GLOBAL_PHASE} && ${^GLOBAL_PHASE} ne 'START' ) {
        no warnings 'redefine';
        *_init_once = sub { };
    }

    return;
}

sub _get_cached_colors {    # for testing
    return \%_cached_colors;
}

#/usr/local/cpanel/3rdparty/bin/perl -MTerm::ANSIColor -MData::Dumper -e 'print Dumper(\%Term::ANSIColor::ATTRIBUTES);'|less
# See http://ethanschoonover.com/solarized XTERM column
my %solarize256 = (
    base03     => 'grey2',
    base02     => 'grey3',
    base01     => 'grey8',
    base00     => 'grey9',
    base0      => 'grey12',
    base1      => 'grey13',
    base2      => 'grey22',
    base3      => 'rgb554',
    yellow     => 'rgb320',
    orange     => 'rgb410',
    red        => 'rgb400',
    magenta    => 'rgb301',
    violet     => 'rgb113',
    blue       => 'rgb025',
    cyan       => 'rgb033',
    green      => 'rgb120',
    on_base03  => 'on_grey2',
    on_base02  => 'on_grey3',
    on_base01  => 'on_grey8',
    on_base00  => 'on_grey9',
    on_base0   => 'on_grey12',
    on_base1   => 'on_grey13',
    on_base2   => 'on_grey22',
    on_base3   => 'on_rgb554',
    on_yellow  => 'on_rgb320',
    on_orange  => 'on_rgb410',
    on_red     => 'on_rgb400',
    on_magenta => 'on_rgb301',
    on_violet  => 'on_rgb113',
    on_blue    => 'on_rgb025',
    on_cyan    => 'on_rgb033',
    on_green   => 'on_rgb120'

);

# See http://ethanschoonover.com/solarized TERMCOL column
my %solarize16 = (
    base03    => 'bright_black',
    base02    => 'black',
    base01    => 'bright_green',
    base00    => 'bright_yellow',
    base0     => 'bright_blue',
    base1     => 'bold',               # cyan looked really bad in transfer restores
    base2     => 'white',
    base3     => 'bright_white',
    on_base03 => 'on_bright_black',
    on_base02 => 'on_black',
    on_base01 => 'on_bright_green',
    on_base00 => 'on_bright_yellow',
    on_base0  => 'on_bright_blue',
    on_base1  => 'on_bright_cyan',
    on_base2  => 'on_white',
    on_base3  => 'on_bright_white',
    violet    => 'bright_magenta',
    orange    => 'bright_red',
);

# See http://ethanschoonover.com/solarized TERMCOL column (remove bright_)
my %solarize8 = (
    base03    => 'black',
    base02    => 'black',
    base01    => 'green',
    base00    => 'yellow',
    base0     => 'blue',
    base1     => 'cyan',
    base2     => 'white',
    base3     => 'white',
    on_base03 => 'on_black',
    on_base02 => 'on_black',
    on_base01 => 'on_green',
    on_base00 => 'on_yellow',
    on_base0  => 'on_blue',
    on_base1  => 'on_cyan',
    on_base2  => 'on_white',
    on_base3  => 'on_white',
    violet    => 'magenta',
    orange    => 'red',
);

sub colored {
    my ( $first, @input ) = @_;

    _init_once();

    _set_cached_palette_ref()                                             if !defined $_cached_max_colors;
    $_is_it_safe_to_colorize = Cpanel::Terminal::it_is_safe_to_colorize() if !defined $_is_it_safe_to_colorize;

    if ( ref $first ) {

        #TODO: In 11.54, move this logic to another module.
        #this module should always colorize.
        return join( '', @input ) if !$_cached_max_colors || !$_is_it_safe_to_colorize;

        Cpanel::LoadModule::load_perl_module('Term::ANSIColor') if !$INC{'Term/ANSIColor.pm'};

        return join(
            q<>,

            # color
            ( $_cached_colors{ $first->[0] } ||= Term::ANSIColor::color( join( ' ', map { $_cached_palette_ref->{$_} || $_ } split( m{\s+}, $first->[0] ) ) ) ),

            # text
            @input,

            # end color
            ANSI_RESET(),
        );
    }
    else {
        #TODO: In 11.54, move this logic to another module;
        #this module should always colorize.
        return $first if !$_cached_max_colors || !$_is_it_safe_to_colorize;

        Cpanel::LoadModule::load_perl_module('Term::ANSIColor') if !$INC{'Term/ANSIColor.pm'};
        return Term::ANSIColor::colored( $first, map { $_cached_palette_ref->{$_} || $_ } @input );
    }
}

sub _set_cached_palette_ref {

    return if defined $_cached_max_colors;

    $_cached_max_colors = Cpanel::Terminal::get_max_colors_for_terminal( $ENV{'TERM'} );

    #Avoid multiple calls into this function.
    $_cached_max_colors ||= 0;

    if ($_cached_max_colors) {
        $_cached_palette_ref = $_cached_max_colors >= 256 ? \%solarize256 : $_cached_max_colors >= 16 ? \%solarize16 : \%solarize8;
    }

    return;
}

1;
