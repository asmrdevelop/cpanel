package Cpanel::Template::Plugin::Resource;

# cpanel - Cpanel/Template/Plugin/Resource.pm      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use base 'Template::Plugin';

=head1 NAME

Cpanel::Template::Plugin::Resource

=head1 DESCRIPTION

Plugin that exposes various Resource resolution related methods to the Template Toolkit pages.

=head1 METHODS

=head2 C<load(CLASS, CONTEXT)>

Internal method that is called when the plugin loads.

=head3 Arguments

Arguments are positional.

=over

=item CLASS - string - Class name of this plugin

=item CONTEXT - object - Template toolkit context.

=back

=head3 Returns

See documentation in Template Toolkit Plugin API for expected return type.

=cut

sub load {
    my ( $class, $context ) = @_;

    my $stash = $context->stash();
    @{$stash}{
        'calculate_mode_css_url',
        'calculate_mode_js_url',
        'get_stylesheet_based_on_direction',
      } = (
        \&calculate_mode_css_url,
        \&calculate_mode_js_url,
        \&get_stylesheet_based_on_direction,
      );

    return $class->SUPER::load($context);
}

=head2 C<calculate_mode_css_url(SOURCE, OPTIMIZED)>

Calculates the production vs debug CSS URL from the simple URL.

=head3 Arguments

Arguments are positional.

=over

=item SOURCE - string

Simple url for the file. Example: sample.css

=item OPTIMIZED - boolean

When true, the optimized file is returned, otherwise the unoptimized file is returned

=back

=head3 Returns

Returns either the optimized path or unoptimized page. The transform varies depending
on where the resource is located to account for various legacy optimization strategies.

=head3 Note

New components should use the .min.css extension exclusively. All other optimization
strategies are considered legacy.

=cut

sub calculate_mode_css_url {
    my ( $source, $optimized ) = @_;

    die "No source provided" if !$source;

    if ( $optimized && index( $source, '_optimized' ) == -1 ) {
        if ( index( $source, 'css2-min/' ) > -1 || index( $source, 'yui/' ) > -1 ) {
            return $source;
        }
        elsif ( index( $source, 'css2/' ) > -1 ) {
            $source =~ s{css2/}{css2-min/};
            return $source;
        }
        elsif ( index( $source, 'cjt/css/' ) > -1 ) {
            $source =~ s{\.css$}{-min.css};
            return $source;
        }
        else {
            if ( index( $source, '.min.css' ) == -1 ) {
                $source =~ s{\.css$}{.min.css};
                return $source;
            }
            else {
                return $source;
            }
        }
    }
    else {
        return $source;
    }
}

=head2 C<calculate_mode_js_url(SOURCE, OPTIMIZED)>

Calculates the production vs debug JavaScript URL from the simple URL.

=head3 Arguments

Arguments are positional.

=over

=item SOURCE - string

Simple url for the file. Example: sample.js

=item OPTIMIZED - boolean

When true, the optimized file is returned, otherwise the unoptimized file is returned

=back

=head3 Returns

Returns either the optimized path or unoptimized page. The transform varies depending
on where the resource is located to account for various legacy optimization strategies.

=head3 Note

New components should use the .min.js extension exclusively. All other optimization
strategies are considered legacy.

=cut

sub calculate_mode_js_url {
    my ( $source, $optimized ) = @_;

    die "No source provided" if !$source;

    if ( $optimized && index( $source, '_optimized' ) == -1 ) {
        if ( index( $source, 'js2-min/' ) > -1 || index( $source, '/yui/' ) == 0 || index( $source, 'libraries/editarea/' ) == 0 ) {
            return $source;
        }
        elsif ( index( $source, 'js2/' ) > -1 ) {
            $source =~ s{js2/}{js2-min/};
            return $source;
        }
        elsif ( index( $source, 'cjt/' ) > -1 ) {
            $source =~ s{\.js$}{-min.js};
            return $source;
        }
        else {
            if ( index( $source, '.min.js' ) == -1 ) {
                $source =~ s{\.js$}{.min.js};
                return $source;
            }
            else {
                return $source;
            }
        }
    }
    else {
        return $source;
    }
}

=head2 C<get_stylesheet_based_on_direction(SOURCE, isRTL)>

Modifies a css stylesheet name to reflect if it is an RTL style or not.

=head3 Arguments

Arguments are positional.

=over

=item SOURCE - string

Simple url of the file. Example: sample.css

=item isRTL - boolean

When true, the RTL filename is returned.  When false, a non-RTL filename is returned (with references to rtl stripped out).

=back

=head3 Returns

Returns a new filename that reflects RTL status.

=cut

sub get_stylesheet_based_on_direction {
    my ( $source, $isRTL ) = @_;
    if ( !$source )           { return $source; }    #If the string is empty or null, send it back as-is.
    if ( $source !~ /.css$/ ) { return $source; }    #Return any non-css file as-is.
    if ($isRTL) {                                    #This is an RTL file
        if ( $source !~ /.rtl./ ) {                  #The string contains RTL
            if ( $source !~ /.min./ ) {              #Non-minimized!
                $source =~ s/.css$/.rtl.css/;        #insert an RTL before the CSS
            }
            else {                                   #Minimized!
                $source =~ s/.min.css$/.rtl.min.css/;    #Insert an RTL before the MIN
            }
        }
    }
    else {    #This is NOT an RTL file
        $source =~ s/.rtl././;    #Remove RTL if present
    }
    return $source;
}

1;
