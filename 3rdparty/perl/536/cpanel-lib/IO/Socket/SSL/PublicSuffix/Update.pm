
use strict;
use warnings;

package IO::Socket::SSL::PublicSuffix::Update;
use Carp;

# for updates
use constant URL => 'http://publicsuffix.org/list/effective_tld_names.dat';

=head1 NAME

IO::Socket::SSL::PublicSuffix::Update - update the public suffix list

=head1 UPDATING

You may find that your need to update the public suffix list without updating this module.

To update this file with the current list:

    Use the included utility: update_latest_public_suffix

    OR

    perl -MIO::Socket::SSL::PublicSuffix -e 'IO::Socket::SSL::PublicSuffix::update_self_from_url()'

This will create a IO::Socket::SSL::PublicSuffix::Latest which will be preferred
over the IO::Socket::SSL::PublicSuffix::BuiltIn module that ships with
IO::Socket::SSL::PublicSuffix

=cut

sub update_self_from_url {
    my $url    = shift || URL();
    my $module = shift || 'Latest';

    require LWP::UserAgent;
    my $resp = LWP::UserAgent->new->get($url)
      or die "no response from $url";
    die "no success url=$url code=" . $resp->code . " " . $resp->message
      if !$resp->is_success;

    return update_self_from_string( $resp->decoded_content, $module );
}

sub update_self_from_string {
    my $content = shift;
    my $module  = shift || 'Latest';

    require Data::Dumper;
    require File::Spec;

    # We have a template file in PublicSuffix that we use to build
    # the .pm file
    my ( $volume, $target_directory, $file ) = File::Spec->splitpath(__FILE__);
    my $dst            = File::Spec->catfile( $target_directory, "$module.pm" );
    my $dst_build_file = "$dst.build";
    -w $target_directory or -w $dst or die "cannot write $dst: $!";
    my $template_file = File::Spec->catfile( $target_directory, "Data.pm.template" );
    my $template_code;
    open( my $template_fh, '<', $template_file ) or die "open($template_file): $!";
    {
        local $/;
        $template_code = readline($template_fh);
        defined $template_code or die "Failed to read template: $template_file: $!";
    }
    open( my $build_fh, '>:utf8', $dst_build_file ) or die "open($dst_build_file): $!";

    # We want to ignore all the content after ===END ICANN DOMAINS
    # as this contains domains we do not want to include
    # see RT#99702
    $content =~ s{^// ===END ICANN DOMAINS.*}{}ms
      or die "cannot find END ICANN DOMAINS";
    my $tree_hr           = IO::Socket::SSL::PublicSuffix::build_tree_from_string_ref( \$content );
    my $tree_code         = Data::Dumper->new( [$tree_hr], ['tree'] )->Quotekeys(0)->Purity(1)->Indent(0)->Terse(1)->Deepcopy(1)->Dump();
    my $build_time_string = gmtime() . ' UTC';
    $template_code =~ s{\Q[% tree_code %]\E}{$tree_code}g;
    $template_code =~ s{\Q[% module %]\E}{$module}g;
    $template_code =~ s{\Q[% build_time_string %]\E}{$build_time_string}g;
    print {$build_fh} $template_code;
    close($build_fh) or die "close($dst_build_file): $!";
    rename( $dst_build_file, $dst ) or die "Failed to install $dst from $dst_build_file: $!";
    return;
}

1;
