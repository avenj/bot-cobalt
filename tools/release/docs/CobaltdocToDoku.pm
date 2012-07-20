package CobaltdocToDoku;
our $VERSION = '0.013';

## a Pod::Simple::Wiki class to create DokuWiki txt for cobalt2's POD
## does cobalt2-specific stuff and a bit of a mess, hence not on CPAN

use Pod::Simple::Wiki;
use strict;
use vars qw(@ISA $VERSION);


@ISA     = qw(Pod::Simple::Wiki);
$VERSION = '0.08';

my $tags = {
            '<b>'    => '**',
            '</b>'   => '**',
            '<i>'    => '//',
            '</i>'   => '//',
            '<tt>'   => '__',
            '</tt>'  => '__',
            '<pre>'  => "<code perl>\n",
            '</pre>' => "\n</code>\n\n",

            '<h1>'   => "======",
            '</h1>'  => "======\n\n",
            '<h2>'   => "=====",
            '</h2>'  => "=====\n\n",
            '<h3>'   => "====",
            '</h3>'  => "====\n\n",
            '<h4>'   => "===",
            '</h4>'  => "===\n\n",
           };

sub new {
    my $class                   = shift;
    my $self                    = Pod::Simple::Wiki->new('wiki', @_);
       $self->{_tags}           = $tags;

    bless  $self, $class;
    return $self;
}

# _skip_headings()
#
# Formatting in headings doesn't look great or is ignored in some formats.
#
sub _skip_headings {
    my $self = shift;

    if ($self->{_in_head1} or
        $self->{_in_head2} or
        $self->{_in_head3} or
        $self->{_in_head4})
    {
      return 1;
    }
}


###############################################################################
#
# _indent_item()
#
# Indents an "over-item" to the correct level.
#
sub _indent_item {
    my $self         = shift;
    my $item_type    = $_[0];
    my $item_param   = $_[1];
    my $indent_level = $self->{_item_indent};

    if    ($item_type eq 'bullet') {
         $self->_append('  ' x $indent_level . '* ');
    }
    elsif ($item_type eq 'number') {
         $self->_append('  ' x $indent_level . '# ');
    }
    ## no indent operator in dokuwiki, use a bullet list:
    elsif ($item_type eq 'text') {
         $self->_append('  ' x $indent_level . '* ');
    }
}

#
# _handle_text()
#
# Perform any necessary transforms on the text. 
sub _handle_text {
    my $self = shift;
    my $text = $_[0];

    # Only escape words in paragraphs
    if (not $self->{_in_Para}) {
        $self->{_wiki_text} .= $text;
        return;
    }

    # Split the text into tokens but maintain the whitespace
    my @tokens = split /(\s+)/, $text;

    # Escape any tokens here, if necessary.
    # DokuWiki escape is <nowiki></nowiki>
    for (@tokens) {
      next unless /\S/;
#      next if m[^(ht|f)tp://];             # Ignore URLs
      ## escape DokuWiki formatting:
      s@(([*}{%'[\]/_\\#=])\2+)@<nowiki>$1</nowiki>@g;
    }

    # Rejoin the tokens and whitespace.
    $self->{_wiki_text} .= join '', @tokens;
}



#
# Functions to deal with =over ... =back regions for
# Bulleted lists
# Numbered lists
# Text     lists
# Block    lists
#
sub _end_item_text     {$_[0]->_output("\n")}



## Functions to deal with links.

sub _start_L {
  my ($self, $attr) = @_;

  unless ($self->_skip_headings) {
    $self->_append('');         # In case we have _indent_text pending
    $self->_output; # Flush the text buffer, so it will contain only the link text
    $self->{_link_attr} = $attr; # Save for later
  } # end unless skipping formatting because in heading
} # end _start_L

sub _end_L {
  my $self = $_[0];

  my $attr = delete $self->{_link_attr};

  if ($attr and my $method = $self->can('_format_link')) {
    $self->{_wiki_text} = $method->($self, $self->{_wiki_text}, $attr);
  } # end if link to be processed
} # end _end_L


# _format_link

sub _format_link {
  my ($self, $text, $attr) = @_;

  if ($attr->{type} eq 'url') {
    my $link = $attr->{to};

    return $link if $attr->{'content-implicit'};
    return "[[$link|$text]]";
  } # end if hyperlink to URL

  # Manpage:
  if ($attr->{type} eq 'man') {
    return "__".$text."__" if $attr->{'content-implicit'};
    return "$text (__".$attr->{to}."__)";
  }

  die "unknown link type? $attr->{type}" unless $attr->{type} eq 'pod';

  # Handle a link within this page:
  return "[[#$attr->{section}|$text]]" unless defined $attr->{to};

  ## :: POD syntax won't work very well with doku ...
  ## strip down to one :
  ## then you can lay out files fairly normally
  my $to = $attr->{to};
  $to =~ s/:{2}/:/g;

  ## if this is a Cobalt:: or cobalt2* page, link within cobalt:docs:
  if ($attr->{to} =~ /^(Bot::Cobalt(::)?|cobalt2-)/) {
    $to = "bots:cobalt:docs:" . $to
  } else {
    ## if this isn't a Cobalt:: or Manual:: page it's probably CPANable:
    my $cpans = "http://search.cpan.org/perldoc?";
    $to = $cpans . $attr->{to};
  }

  # Handle a link to a specific section in another page:
  return "[[$to#$attr->{section}|$text]]" if defined $attr->{section};

  return "[[$to|$attr->{to}]]" if $attr->{'content-implicit'};

  return "[[$to|$text]]";
}



#
# _start_Para()
#
# Special handling for paragraphs that are part of an "over" block.
#
sub _start_Para {
    my $self         = shift;
    my $indent_level = $self->{_item_indent};

    if ($self->{_in_over_block}) {
        # 
    }
}


1;


