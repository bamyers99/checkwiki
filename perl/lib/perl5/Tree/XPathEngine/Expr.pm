# $Id: /tree-xpathengine/trunk/lib/Tree/XPathEngine/Expr.pm 19 2006-02-13T10:40:57.804258Z mrodrigu  $

package Tree::XPathEngine::Expr;
use strict;

sub new {
    my $class = shift;
    my ($pp) = @_;
    bless { predicates => [], pp => $pp }, $class;
}

sub as_string {
    my $self = shift;
    local $^W; # Use of uninitialized value! grrr
    my $string = "(" . $self->{lhs}->as_string;
    $string .= " " . $self->{op} . " " if defined $self->{op};
    $string .= $self->{rhs}->as_string if defined $self->{rhs};
    $string .= ")";
    foreach my $predicate (@{$self->{predicates}}) {
        $string .= "[" . $predicate->as_string . "]";
    }
    return $string;
}


sub set_lhs {
    my $self = shift;
    $self->{lhs} = $_[0];
}

sub set_op {
    my $self = shift;
    $self->{op} = $_[0];
}

sub set_rhs {
    my $self = shift;
    $self->{rhs} = $_[0];
}

sub push_predicate {
    my $self = shift;
    
    die "Only 1 predicate allowed on FilterExpr in W3C XPath 1.0"
            if @{$self->{predicates}};
    
    push @{$self->{predicates}}, $_[0];
}

sub get_lhs { $_[0]->{lhs}; }
sub get_rhs { $_[0]->{rhs}; }
sub get_op { $_[0]->{op}; }

sub evaluate {
    my $self = shift;
    my $node = shift;
    
    # If there's an op, result is result of that op.
    # If no op, just resolve Expr
    
#    warn "Evaluate Expr: ", $self->as_string, "\n";
    
    my $results;
    
    if ($self->{op}) {
        die ("No RHS of ", $self->as_string) unless $self->{rhs};
        $results = $self->_op_eval($node);
    }
    else {
        $results = $self->{lhs}->evaluate($node);
    }
    
    if (my @predicates = @{$self->{predicates}}) {
        if (!$results->isa('Tree::XPathEngine::NodeSet')) {
            die "Can't have predicates execute on object type: " . ref($results);
        }
        
        # filter initial nodeset by each predicate
        foreach my $predicate (@{$self->{predicates}}) {
            $results = $self->filter_by_predicate($results, $predicate);
        }
    }
    
    return $results;
}

sub _op_eval {
    my $self = shift;
    my $node = shift;
    
    my $op = $self->{op};
    
    for ($op) {
        /^or$/    && do {
                    return _op_or($node, $self->{lhs}, $self->{rhs});
                };
        /^and$/    && do {
                    return _op_and($node, $self->{lhs}, $self->{rhs});
                };
        /^=~$/   && do {
                    return _op_match($node, $self->{lhs}, $self->{rhs});
                };
        /^!~$/   && do {
                    return _op_not_match($node, $self->{lhs}, $self->{rhs});
                };
        /^=$/    && do {
                    return _op_equals($node, $self->{lhs}, $self->{rhs});
                };
        /^!=$/    && do {
                    return _op_nequals($node, $self->{lhs}, $self->{rhs});
                };
        /^<=$/    && do {
                    return _op_le($node, $self->{lhs}, $self->{rhs});
                };
        /^>=$/    && do {
                    return _op_ge($node, $self->{lhs}, $self->{rhs});
                };
        /^>$/    && do {
                    return _op_gt($node, $self->{lhs}, $self->{rhs});
                };
        /^<$/    && do {
                    return _op_lt($node, $self->{lhs}, $self->{rhs});
                };
        /^\+$/    && do {
                    return _op_plus($node, $self->{lhs}, $self->{rhs});
                };
        /^-$/    && do {
                    return _op_minus($node, $self->{lhs}, $self->{rhs});
                };
        /^div$/    && do {
                    return _op_div($node, $self->{lhs}, $self->{rhs});
                };
        /^mod$/    && do {
                    return _op_mod($node, $self->{lhs}, $self->{rhs});
                };
        /^\*$/    && do {
                    return _op_mult($node, $self->{lhs}, $self->{rhs});
                };
        /^\|$/    && do {
                    return _op_union($node, $self->{lhs}, $self->{rhs});
                };
        
        die "No such operator, or operator unimplemented in ", $self->as_string, "\n";
    }
}

# Operators

use Tree::XPathEngine::Boolean;

sub _op_or {
    my ($node, $lhs, $rhs) = @_;
    if($lhs->evaluate($node)->xpath_to_boolean->value) {
        return Tree::XPathEngine::Boolean->_true;
    }
    else {
        return $rhs->evaluate($node)->xpath_to_boolean;
    }
}

sub _op_and {
    my ($node, $lhs, $rhs) = @_;
    if( ! $lhs->evaluate($node)->xpath_to_boolean->value ) {
        return Tree::XPathEngine::Boolean->_false;
    }
    else {
        return $rhs->evaluate($node)->xpath_to_boolean;
    }
}

sub _op_equals {
    my ($node, $lhs, $rhs) = @_;

    my $lh_results = $lhs->evaluate($node);
    my $rh_results = $rhs->evaluate($node);
    
    if ($lh_results->isa('Tree::XPathEngine::NodeSet') &&
            $rh_results->isa('Tree::XPathEngine::NodeSet')) {
        # _true if and only if there is a node in the
        # first set and a node in the second set such
        # that the result of performing the comparison
        # on the string-values of the two nodes is true.
        foreach my $lhnode ($lh_results->get_nodelist) {
            foreach my $rhnode ($rh_results->get_nodelist) {
                if ($lhnode->xpath_string_value eq $rhnode->xpath_string_value) {
                    return Tree::XPathEngine::Boolean->_true;
                }
            }
        }
        return Tree::XPathEngine::Boolean->_false;
    }
    elsif (($lh_results->isa('Tree::XPathEngine::NodeSet') ||
            $rh_results->isa('Tree::XPathEngine::NodeSet')) &&
            (!$lh_results->isa('Tree::XPathEngine::NodeSet') ||
             !$rh_results->isa('Tree::XPathEngine::NodeSet'))) {
        # (that says: one is a nodeset, and one is not a nodeset)
        
        my ($nodeset, $other);
        if ($lh_results->isa('Tree::XPathEngine::NodeSet')) {
            $nodeset = $lh_results;
            $other = $rh_results;
        }
        else {
            $nodeset = $rh_results;
            $other = $lh_results;
        }
        
        # _true if and only if there is a node in the
        # nodeset such that the result of performing
        # the comparison on <type>(string_value($node))
        # is true.
        if ($other->isa('Tree::XPathEngine::Number')) {
            foreach my $node ($nodeset->get_nodelist) {
                local $^W; # argument isn't numeric
                if ($node->xpath_string_value == $other->value) {
                    return Tree::XPathEngine::Boolean->_true;
                }
            }
        }
        elsif ($other->isa('Tree::XPathEngine::Literal')) {
            foreach my $node ($nodeset->get_nodelist) {
                if ($node->xpath_string_value eq $other->value) {
                    return Tree::XPathEngine::Boolean->_true;
                }
            }
        }
        elsif ($other->isa('Tree::XPathEngine::Boolean')) {
            if ($nodeset->xpath_to_boolean->value == $other->value) {
                return Tree::XPathEngine::Boolean->_true;
            }
        }

        return Tree::XPathEngine::Boolean->_false;
    }
    else { # Neither is a nodeset
        if ($lh_results->isa('Tree::XPathEngine::Boolean') ||
            $rh_results->isa('Tree::XPathEngine::Boolean')) {
            # if either is a boolean
            if ($lh_results->xpath_to_boolean->value == $rh_results->xpath_to_boolean->value) {
                return Tree::XPathEngine::Boolean->_true;
            }
            return Tree::XPathEngine::Boolean->_false;
        }
        elsif ($lh_results->isa('Tree::XPathEngine::Number') ||
                $rh_results->isa('Tree::XPathEngine::Number')) {
            # if either is a number
            local $^W; # 'number' might result in undef
            if ($lh_results->xpath_to_number->value == $rh_results->xpath_to_number->value) {
                return Tree::XPathEngine::Boolean->_true;
            }
            return Tree::XPathEngine::Boolean->_false;
        }
        else {
            if ($lh_results->xpath_to_literal->value eq $rh_results->xpath_to_literal->value) {
                return Tree::XPathEngine::Boolean->_true;
            }
            return Tree::XPathEngine::Boolean->_false;
        }
    }
}

sub _op_match 
  { my ($node, $lhs, $rhs) = @_;

    my $lh_results = $lhs->evaluate($node);
    my $rh_results = $rhs->evaluate($node);
    my $rh_value   = $rh_results->xpath_string_value;

    if ($lh_results->isa('Tree::XPathEngine::NodeSet') ) 
      { foreach my $lhnode ($lh_results->get_nodelist) 
          { if ($lhnode->xpath_string_value=~ m/$rh_value/) # / is important here, regexp is / delimited
              { return Tree::XPathEngine::Boolean->_true; }
          }
        return Tree::XPathEngine::Boolean->_false;
      }
    else
      { return $lh_results->xpath_string_value =~  m!$rh_value! ?
               Tree::XPathEngine::Boolean->_true : Tree::XPathEngine::Boolean->_false;
      }
  }
  
sub _op_not_match 
  { my ($node, $lhs, $rhs) = @_;

    my $lh_results = $lhs->evaluate($node);
    my $rh_results = $rhs->evaluate($node);
    my $rh_value   = $rh_results->xpath_string_value;
    
    if ($lh_results->isa('Tree::XPathEngine::NodeSet') ) 
      { foreach my $lhnode ($lh_results->get_nodelist) 
          { if ($lhnode->xpath_string_value!~ m!$rh_value!) 
              { return Tree::XPathEngine::Boolean->_true; }
          }
        return Tree::XPathEngine::Boolean->_false;
      }
    else
      { return $lh_results->xpath_string_value !~  m!$rh_value! ?
               Tree::XPathEngine::Boolean->_true : Tree::XPathEngine::Boolean->_false;
      }
  }

sub _op_nequals {
    my ($node, $lhs, $rhs) = @_;
    if (_op_equals($node, $lhs, $rhs)->value) {
        return Tree::XPathEngine::Boolean->_false;
    }
    return Tree::XPathEngine::Boolean->_true;
}

sub _op_le {
    my ($node, $lhs, $rhs) = @_;
    _op_ge($node, $rhs, $lhs);
}

sub _op_ge {
    my ($node, $lhs, $rhs) = @_;

    my $lh_results = $lhs->evaluate($node);
    my $rh_results = $rhs->evaluate($node);
    
    if ($lh_results->isa('Tree::XPathEngine::NodeSet') &&
        $rh_results->isa('Tree::XPathEngine::NodeSet')) {

        foreach my $lhnode ($lh_results->get_nodelist) {
            foreach my $rhnode ($rh_results->get_nodelist) {
                my $lhNum = Tree::XPathEngine::Number->new($lhnode->xpath_string_value);
                my $rhNum = Tree::XPathEngine::Number->new($rhnode->xpath_string_value);
                local $^W; # Use of uninitialized value!
                if ($lhNum->value >= $rhNum->value) {
                    return Tree::XPathEngine::Boolean->_true;
                }
            }
        }
        return Tree::XPathEngine::Boolean->_false;
    }
    elsif (($lh_results->isa('Tree::XPathEngine::NodeSet') ||
            $rh_results->isa('Tree::XPathEngine::NodeSet')) &&
            (!$lh_results->isa('Tree::XPathEngine::NodeSet') ||
             !$rh_results->isa('Tree::XPathEngine::NodeSet'))) {
        # (that says: one is a nodeset, and one is not a nodeset)

        if ($lh_results->isa('Tree::XPathEngine::NodeSet')) {
            foreach my $node ($lh_results->get_nodelist) {
                local $^W; # Use of uninitialized value!
                if ($node->xpath_to_number->value >= $rh_results->xpath_to_number->value) {
                    return Tree::XPathEngine::Boolean->_true;
								}
            }
        }
        else {
            foreach my $node ($rh_results->get_nodelist) {
                local $^W; # Use of uninitialized value!
                if ( $lh_results->xpath_to_number->value >= $node->xpath_to_number->value) {
                    return Tree::XPathEngine::Boolean->_true;
                }
            }
				}
        return Tree::XPathEngine::Boolean->_false;
    }
    else { # Neither is a nodeset
        if ($lh_results->isa('Tree::XPathEngine::Boolean') ||
            $rh_results->isa('Tree::XPathEngine::Boolean')) {
            # if either is a boolean
            if ($lh_results->xpath_to_boolean->xpath_to_number->value
                    >= $rh_results->xpath_to_boolean->xpath_to_number->value) {
                return Tree::XPathEngine::Boolean->_true;
            }
        }
        else {
            if ($lh_results->xpath_to_number->value >= $rh_results->xpath_to_number->value) {
                return Tree::XPathEngine::Boolean->_true;
            }
        }
        return Tree::XPathEngine::Boolean->_false;
    }
}

sub _op_gt {
    my ($node, $lhs, $rhs) = @_;

    my $lh_results = $lhs->evaluate($node);
    my $rh_results = $rhs->evaluate($node);
    
    if ($lh_results->isa('Tree::XPathEngine::NodeSet') &&
        $rh_results->isa('Tree::XPathEngine::NodeSet')) {

        foreach my $lhnode ($lh_results->get_nodelist) {
            foreach my $rhnode ($rh_results->get_nodelist) {
                my $lhNum = Tree::XPathEngine::Number->new($lhnode->xpath_string_value);
                my $rhNum = Tree::XPathEngine::Number->new($rhnode->xpath_string_value);
                local $^W; # Use of uninitialized value!
                if ($lhNum->value > $rhNum->value) {
                    return Tree::XPathEngine::Boolean->_true;
                }
            }
        }
        return Tree::XPathEngine::Boolean->_false;
    }
    elsif (($lh_results->isa('Tree::XPathEngine::NodeSet') ||
            $rh_results->isa('Tree::XPathEngine::NodeSet')) &&
            (!$lh_results->isa('Tree::XPathEngine::NodeSet') ||
             !$rh_results->isa('Tree::XPathEngine::NodeSet'))) {
        # (that says: one is a nodeset, and one is not a nodeset)

        if ($lh_results->isa('Tree::XPathEngine::NodeSet')) {
            foreach my $node ($lh_results->get_nodelist) {
                local $^W; # Use of uninitialized value!
                if ($node->xpath_to_number->value > $rh_results->xpath_to_number->value) {
                    return Tree::XPathEngine::Boolean->_true;
								}
            }
        }
        else {
            foreach my $node ($rh_results->get_nodelist) {
                local $^W; # Use of uninitialized value!
                if ( $lh_results->xpath_to_number->value > $node->xpath_to_number->value) {
                    return Tree::XPathEngine::Boolean->_true;
                }
            }
				}
        return Tree::XPathEngine::Boolean->_false;
    }
    else { # Neither is a nodeset
        if ($lh_results->isa('Tree::XPathEngine::Boolean') ||
            $rh_results->isa('Tree::XPathEngine::Boolean')) {
            # if either is a boolean
            if ($lh_results->xpath_to_boolean->value > $rh_results->xpath_to_boolean->value) {
                return Tree::XPathEngine::Boolean->_true;
            }
        }
        else {
            if ($lh_results->xpath_to_number->value > $rh_results->xpath_to_number->value) {
                return Tree::XPathEngine::Boolean->_true;
            }
        }
        return Tree::XPathEngine::Boolean->_false;
    }
}

sub _op_lt {
    my ($node, $lhs, $rhs) = @_;
    _op_gt($node, $rhs, $lhs);
}

sub _op_plus {
    my ($node, $lhs, $rhs) = @_;
    my $lh_results = $lhs->evaluate($node);
    my $rh_results = $rhs->evaluate($node);
   
    local $^W;
    my $result =
        $lh_results->xpath_to_number->value
            +
        $rh_results->xpath_to_number->value
            ;
    return Tree::XPathEngine::Number->new($result);
}

sub _op_minus {
    my ($node, $lhs, $rhs) = @_;
    my $lh_results = $lhs->evaluate($node);
    my $rh_results = $rhs->evaluate($node);
    
    local $^W;
    my $result =
        $lh_results->xpath_to_number->value
            -
        $rh_results->xpath_to_number->value
            ;
    return Tree::XPathEngine::Number->new($result);
}

sub _op_div {
    my ($node, $lhs, $rhs) = @_;
    my $lh_results = $lhs->evaluate($node);
    my $rh_results = $rhs->evaluate($node);

    local $^W;
    my $result = eval {
        $lh_results->xpath_to_number->value
            /
        $rh_results->xpath_to_number->value
            ;
    };
    if ($@) {
        # assume divide by zero
        # This is probably a terrible way to handle this! 
        # Ah well... who wants to live forever...
        return Tree::XPathEngine::Literal->new('Infinity');
    }
    return Tree::XPathEngine::Number->new($result);
}

sub _op_mod {
    my ($node, $lhs, $rhs) = @_;
    my $lh_results = $lhs->evaluate($node);
    my $rh_results = $rhs->evaluate($node);
    
    local $^W;
    my $result =
        $lh_results->xpath_to_number->value
            %
        $rh_results->xpath_to_number->value
            ;
    return Tree::XPathEngine::Number->new($result);
}

sub _op_mult {
    my ($node, $lhs, $rhs) = @_;
    my $lh_results = $lhs->evaluate($node);
    my $rh_results = $rhs->evaluate($node);
    
    local $^W;
    my $result =
        $lh_results->xpath_to_number->value
            *
        $rh_results->xpath_to_number->value
            ;
    return Tree::XPathEngine::Number->new($result);
}

sub _op_union {
    my ($node, $lhs, $rhs) = @_;
    my $lh_result = $lhs->evaluate($node);
    my $rh_result = $rhs->evaluate($node);
    
    if ($lh_result->isa('Tree::XPathEngine::NodeSet') &&
            $rh_result->isa('Tree::XPathEngine::NodeSet')) {
        my %found;
        my $results = Tree::XPathEngine::NodeSet->new;
        foreach my $lhnode ($lh_result->get_nodelist) {
            $found{"$lhnode"}++;
            $results->push($lhnode);
        }
        foreach my $rhnode ($rh_result->get_nodelist) {
            $results->push($rhnode)
                    unless exists $found{"$rhnode"};
        }
        return $results->sort->remove_duplicates;
    }
    die "Both sides of a union must be Node Sets\n";
}

sub filter_by_predicate {
    my $self = shift;
    my ($nodeset, $predicate) = @_;
    
    # See spec section 2.4, paragraphs 2 & 3:
    # For each node in the node-set to be filtered, the predicate Expr
    # is evaluated with that node as the context node, with the number
    # of nodes in the node set as the context size, and with the
    # proximity position of the node in the node set with respect to
    # the axis as the context position.
    
    if (!ref($nodeset)) { # use ref because nodeset has a bool context
        die "No nodeset!!!";
    }
    
#    warn "Filter by predicate: $predicate\n";
    
    my $newset = Tree::XPathEngine::NodeSet->new();
    
    for(my $i = 1; $i <= $nodeset->size; $i++) {
        # set context set each time 'cos a loc-path in the expr could change it
        $self->{pp}->_set_context_set($nodeset);
        $self->{pp}->_set_context_pos($i);
        my $result = $predicate->evaluate($nodeset->get_node($i));
        if ($result->isa('Tree::XPathEngine::Boolean')) {
            if ($result->value) {
                $newset->push($nodeset->get_node($i));
            }
        }
        elsif ($result->isa('Tree::XPathEngine::Number')) {
            if ($result->value == $i) {
                $newset->push($nodeset->get_node($i));
            }
        }
        else {
            if ($result->xpath_to_boolean->value) {
                $newset->push($nodeset->get_node($i));
            }
        }
    }
    
    return $newset;
}

1;

__END__
=head1 NAME

Tree::XPathEngine::Expr - handles expressions in XPath queries

=head1 METHODS

=head2 new

=head2 op_xml

=head2 get_lhs

=head2 set_lhs

=head2 get_rhs

=head2 set_rhs

=head2 push_predicate

=head2 set_op

=head2 get_op

=head2 evaluate

=head2 filter_by_predicate

=head2 as_string

dump the expression as a string

=head2 as_xml

dump the expression as xml
