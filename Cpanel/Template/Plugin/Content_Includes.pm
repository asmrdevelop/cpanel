package Cpanel::Template::Plugin::Content_Includes;

# cpanel - Cpanel/Template/Plugin/Content_Includes.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use warnings;
use strict;

use base 'Template::Plugin';

use Cpanel::Debug    ();
use Cpanel::Template ();

=head1 NAME

Cpanel::Template::Plugin::Content_Includes - Provides users the ability to include templates from the defined custom include path.

=head1 SYNOPSIS

    [% USE Content_Includes %]
    [% Content_Includes.render ('template_file_to_load.tmpl') %]
    [% END -%]

=head1 METHODS

=over 8

=item B<load>

This method is called by the Template Toolkit when the plugin module is first loaded.

It initializes the singleton that will be returned on subsequent calls to L<new>.

Also see L<http://template-toolkit.org/docs/modules/Template/Plugin.html#method_load>

=cut

sub load {
    my ($class) = @_;
    my $plugin = {};
    return bless $plugin, $class;
}

=item B<new>

This method is called to instantiate a new plugin object for the USE directive.

It returns the singleton initiated in L<load>.

Also see L<http://template-toolkit.org/docs/modules/Template/Plugin.html#method_new>

=cut

sub new {
    my ( $self, $context, @args ) = @_;
    return $self;
}

=item B<render>

Returns the processed output from the template file.

Returns an empty string if the template is not present in the include path, or if there was an error processing the template.

See documentation on Content_Includes for more information on file formatting and usage.

B<Args>:

One required argument: the filename of the template to load.

=cut

sub render {
    my ( $self, $template_name, $data ) = @_;
    $template_name ||= "";
    $data //= {};

    my $include_path  = "/var/cpanel/customizations/content_includes";
    my $template_file = $include_path . "/" . $template_name;

    #Return a blank string silently.  Do not log this as an error to avoid spamming their log on failed checks.
    if ( !_filecheck($template_file) ) {
        return "";
    }

    #Ensure that the template's application and theme match the current application and theme
    my ( $app, $theme, $item ) = split( '_', $template_name );
    $app   ||= "";
    $theme ||= "";
    if ( $app ne "cpanel" ) {
        Cpanel::Debug::log_warn("Failed to process template: '$template_file' - Error: The only application currently supported is 'cpanel'");
        return "";
    }

    my $user_theme = $Cpanel::CPDATA{'RS'};
    if ( $theme ne $user_theme ) {
        Cpanel::Debug::log_warn("Failed to process template: '$template_file' - Error: The template theme $theme does not match user theme $user_theme");
        return "";
    }

    my ( $success, $output ) = Cpanel::Template::process_template(
        'cpanel_injected',
        {
            'print'         => 0,
            'template_file' => $template_file,
            'app'           => $template_file,
            %$data
        },
    );

    if ( $success && ref $output eq 'SCALAR' ) { return $$output; }

    if ( !$success ) {
        Cpanel::Debug::log_warn("Failed to process template: '$template_file' - Error: $output");
        return "";
    }
}

=back

=cut

#Spun off into a mockable function for testability
sub _filecheck {
    my ($file) = @_;
    return -f $file;
}

1;
