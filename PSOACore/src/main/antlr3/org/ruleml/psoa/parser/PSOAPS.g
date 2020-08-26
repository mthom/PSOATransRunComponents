/*
 * Grammar for parsing PSOA RuleML presentation syntax.
 */

grammar PSOAPS;

options
{
    output = AST;
    k = 1;  // limit to one-step look ahead for efficient parsing
    ASTLabelType = CommonTree;
}

tokens
{
    PSOA;
    OIDLESSEMBATOM;
    TUPLE;
    SLOT;
    LITERAL;
    SHORTCONST;
    IRI;
    NUMBER;
    LOCAL;
    FALSITY;
    DEPSIGN;
}

@header
{
    package org.ruleml.psoa.parser;

    import java.util.List;
    import java.util.ArrayList;
    import java.util.Set;
    import java.util.HashSet;
    import java.util.Map;
    import java.util.HashMap;

    import org.ruleml.psoa.transformer.PSOARuntimeException;
}

@lexer::header {
    package org.ruleml.psoa.parser;
}

@lexer::members {
    private boolean printDeprecatedCommentWarning = true;
}

@members
{
	private List<String[]> m_imports = new ArrayList<String[]>();
	private Set<String> m_localConsts = new HashSet<String>();
    private Map<String, String> m_namespaceTable = new HashMap<String, String>();
    private ParserConfig m_config;
    private static Set<String> s_numberTypeIRIs = new HashSet();
    private static String s_stringIRI = "http://www.w3.org/2001/XMLSchema#string";

    static
    {
       s_numberTypeIRIs.add("http://www.w3.org/2001/XMLSchema#integer");
       s_numberTypeIRIs.add("http://www.w3.org/2001/XMLSchema#double");
       s_numberTypeIRIs.add("http://www.w3.org/2001/XMLSchema#long");
    }

    private static boolean fastStringEquals(String s1, String s2)
    {
        return s1.hashCode() == s2.hashCode() && s1.equals(s2);
    }

    /**
     * Get the full IRI form of an IRI prefix
    */
    protected String getNamespace(String prefix)
    {
    	String ns = m_namespaceTable.get(prefix);
    	if (ns == null)
    		throw new PSOARuntimeException("Namespace prefix " + prefix + " used but not defined");

    	return ns;
    }

    /**
     * Set the full IRI of an IRI prefix
    */
	protected void setNamespace(String ns, String iri) {
		String oldIRI = m_namespaceTable.put(ns, iri);
		if (oldIRI != null && !oldIRI.equals(iri))
		{
			throw new PSOARuntimeException("Redefinition of namespace prefix " + ns);
		}
	}

	/**
     * Get full IRI from a namespace-prefixed IRI
    */
	protected String getFullIRI(String ns, String localName)
	{
		return getNamespace(ns) + localName;
	}

    public Map<String, String> getNamespaceTable()
    {
    	return m_namespaceTable;
    }

	public List<String[]> getImports()
	{
		return m_imports;
	}

	public Set<String> getLocalConsts()
	{
		return m_localConsts;
	}

    private CommonTree getTupleTree(List list_terms, int length)
    {
        CommonTree root = (CommonTree)adaptor.nil();
        for (int i = 0; i < length; i++)
            adaptor.addChild(root, list_terms.get(i));
        return root;
    }

    private String getStrValue(String str)
    {
        return str.substring(1, str.length() - 1);
    }

    public void setParserConfig(ParserConfig config) {
    	m_config = config;
    }

    public void checkPrecedingWhitespace() {
    	if (input.get(input.index() - 1).getType() != WHITESPACE) {
    		throw new PSOARuntimeException("Whitespace is expected before " + input.get(input.index()).getText());
    	}
    }
    
    public void checkNoPrecedingWhitespace() {
    	if (input.get(input.index() - 1).getType() == WHITESPACE) {
    		throw new PSOARuntimeException("There must be no whitespace before " + input.get(input.index()).getText());
    	}
    }

    public boolean hasPrecedingWhitespace() {
    	return (input.get(input.index() - 1).getType() == WHITESPACE);
    }
}

document
    :   DOCUMENT LPAR base? prefix* importDecl* group? RPAR
        -> ^(DOCUMENT base? prefix* importDecl* group?)
    ;

query[Map<String, String> nsTable]
@init
{
	if (nsTable != null)
		m_namespaceTable = nsTable;
}
    :   formula;

base
    :   BASE LPAR IRI_REF RPAR -> ^(BASE IRI_REF)
    ;

prefix
    :   PREFIX LPAR NAMESPACE IRI_REF RPAR
	    {
	    	setNamespace($NAMESPACE.text, $IRI_REF.text);
	    }
    -> ^(PREFIX NAMESPACE IRI_REF)
    ;

importDecl
    :   IMPORT LPAR kb=IRI_REF (pf=IRI_REF)? RPAR
    	{
			String[] importDoc = new String[2];
			importDoc[0] = $kb.text;
			if (pf != null)
				importDoc[1] = $pf.text;
			m_imports.add(importDoc);
    	}
	-> ^(IMPORT $kb $pf?)
    ;

group
    :   GROUP LPAR group_element* RPAR -> ^(GROUP group_element*)
    ;

group_element
    :   rule
    |   group
    ;

rule
    :   FORALL variable+ LPAR clause RPAR
        -> ^(FORALL variable+ clause)
    |   clause
    ;

clause
@after
{
    if (!$f1.isValidHead)
        throw new PSOARuntimeException("Unacceptable head formula:" + $f1.text);
}
    :   (f1=formula -> formula) (IMPLICATION f2=formula -> ^(IMPLICATION $clause $f2) )?
    ;

formula returns [boolean isValidHead, boolean isAtomic]
@init
{
   $isValidHead = true; $isAtomic = false;
   boolean hasSubformulas = false;
}
    :   AND LPAR (f=formula { if(!$f.isValidHead) $isValidHead = false; } )+ RPAR -> ^(AND["AND"] formula*)
    |   OR LPAR (formula { hasSubformulas = true; })* RPAR { $isValidHead = false; }
        -> { hasSubformulas }? ^(OR["OR"] formula*)
        -> FALSITY
    |   EXISTS variable+ LPAR f=formula RPAR { } // $isValidHead = $f.isAtomic; }
        -> ^(EXISTS["EXISTS"] variable+ $f)
    |   naf_formula
    |   atomic { $isAtomic = true; } -> atomic
    |   (external_term { $isValidHead = false; } -> external_term)
        ({!hasPrecedingWhitespace()}? psoa_rest { $isAtomic = true; } -> ^(PSOA $formula psoa_rest))?
    ;

naf_formula
    :   NAF LPAR formula RPAR-> ^(NAF["NAF"] formula)
    ;

atomic
@after
{
    if ($tree.getChildCount() == 1 && $left_term.isSimple)
        throw new PSOARuntimeException("Simple term cannot be an atomic formula:" + $left_term.text);
}
    :   left_term=internal_term ((EQUAL | SUBCLASS)^ term)?
    ;

term
    :   internal_term
    |   external_term
    ;

simple_term
    :   constant
    |   variable
    ;

external_term
    :   EXTERNAL LPAR simple_term LPAR (term ({ checkPrecedingWhitespace(); } term)*)? RPAR RPAR
    -> ^(EXTERNAL ^(PSOA ^(INSTANCE simple_term) ^(TUPLE DEPSIGN["+"] term*)))
    ;


internal_term returns [boolean isSimple]
scope
{
    boolean inLTNF;
    int line;
}
@init
{
    $isSimple = true;
    $internal_term::inLTNF = true;
    $internal_term::line = input.LT(1).getLine();
}
@after
{
    if (m_config.ltnfFinding && !$internal_term::inLTNF)
    {
       System.out.println("Finding: Not in left-tuple normal form (LTNF): " + $internal_term.text + " at line " + $internal_term::line);
    }
}
    :   (simple_term -> simple_term)
        (LPAR (tuples_and_slots { $internal_term::inLTNF &= $tuples_and_slots.inLTNF; })? RPAR { $isSimple = false; }
         -> ^(PSOA ^(INSTANCE $internal_term) tuples_and_slots?))?
        ({ !hasPrecedingWhitespace() }? psoa_rest { $isSimple = false; $internal_term::inLTNF &= $psoa_rest.inLTNF; }
         -> ^(PSOA $internal_term psoa_rest))*   
    |   emb_atom_chain { $isSimple = false; $internal_term::inLTNF &= $emb_atom_chain.inLTNF; }         
    ;   

emb_atom_chain_rest
    :   { !hasPrecedingWhitespace() }? psoa_rest
    ; 

emb_atom_chain returns [boolean inLTNF]
    :   (psoa_rest {$emb_atom_chain.inLTNF = $psoa_rest.inLTNF; } -> ^(OIDLESSEMBATOM psoa_rest))
        (emb_atom_chain_rest -> ^(PSOA $emb_atom_chain emb_atom_chain_rest))*
    ;

psoa_rest returns [boolean inLTNF]
scope
{
    boolean tsInLTNF;
}
@init
{
    $psoa_rest::tsInLTNF = true;
}
@after
{
    $inLTNF = $psoa_rest::tsInLTNF;
}
    :   INSTANCE { checkNoPrecedingWhitespace(); } simple_term (LPAR (ts=tuples_and_slots { $psoa_rest::tsInLTNF &= $ts.inLTNF; })? RPAR)?
    -> ^(INSTANCE simple_term) tuples_and_slots?
    ;

/*
 *  tuples_and_slots parses a sequence of tuples and slots inside a PSOA atom.
 *
 *  The analysis considers two cases, distinguished by the presence (absence)
 *  of an implicit tuple, a sequence of terms unenclosed by square brackets.
 *
 *  An implicit tuple:
 *    * cannot be written in an atom containing conventional ("explicit") tuples,
 *    * requires its surrounding atom to be written in left tuple normal form.
 *
 *  An atom without an implicit tuple allows explicit tuples and slots to be
 *  written in any order.
 *
 *  tuples_and_slots keeps a list of terms called "terms" which is non-empty
 *  if and only if:
 *
 *  (1) an implicit tuple is present, or,
 *  (2) a slot is present, or,
 *  (3) both.
 *
 *  The rule expands on the pattern
 *
 *  ALT1: term* term ( SLOT_ARROW term (tuple:"raises error unless term* is empty" | slot)* )?
 *  ALT2: (tuple | slot)+
 *
 *  where the ALT1 and ALT2 alternatives are combined in a context-sensitive way.
 *  This is done to improve error detection and reporting.
 */
tuples_and_slots returns [boolean inLTNF]
scope  // Track the indexes of the earliest slot and latest tuple after it
{
    int firstSlotIndex;
    int lastTupleIndex;
}
@init  // Set initial values satisfying lastTupleIndex < firstSlotIndex (last tuple is before first slot)
{
    $inLTNF = true;
    $tuples_and_slots::firstSlotIndex = Integer.MAX_VALUE;
    $tuples_and_slots::lastTupleIndex = 0;
}
@after // The sequence is in LTNF iff the first slot has lexical index greater than or equal to the last tuple index
{
    $inLTNF = $tuples_and_slots::firstSlotIndex >= $tuples_and_slots::lastTupleIndex;
}
    :   { boolean hasSlot = false; boolean hasExplTuple = false; boolean preSlotArrowTuple = false;
          int line = input.LT(1).getLine();}
        ((terms += term {preSlotArrowTuple = false; }) | (tuple {preSlotArrowTuple = true; hasExplTuple = true; }))
         // If "terms" is non-empty, its contents belong to a single
         // implicit tuple, except for the last term, which is the slot name.
         ({ checkPrecedingWhitespace(); }
         ((terms += term {preSlotArrowTuple = false; }) | (tuple {preSlotArrowTuple = true; hasExplTuple = true; })))*
         ( SLOT_ARROW first_slot_value=term { $tuples_and_slots::firstSlotIndex = input.index(); hasSlot = true; } (slot | (tuple {$tuples_and_slots::lastTupleIndex = input.index(); hasExplTuple = true; }))* )?
         {
            if (hasSlot && preSlotArrowTuple)
            {
                throw new PSOARuntimeException("Explicit tuple as slot name at line " + line);
            }
            else if (hasExplTuple && hasSlot && $terms == null)
            {
                throw new PSOARuntimeException("Missing valid slot name at line " + line);
            }
            else if (hasExplTuple && ((!hasSlot && $terms != null) || (hasSlot && $terms.size() > 1)))
            {
                throw new PSOARuntimeException("Implicit tuple in atom with one or more explicit tuples at line " + line);
            }
        }
    ->  {!hasSlot && hasExplTuple}?  // explicit tuples, no implicit tuple
        tuple+
    ->  {!hasSlot}?  // single implicit tuple
        ^(TUPLE DEPSIGN["+"] {getTupleTree($terms, $terms.size()) } )
    ->  {$terms.size() == 1}?  // no implicit tuple, leading slot
        // normalize to right-slot normal form
        tuple* ^(SLOT DEPSIGN[$SLOT_ARROW.text.substring(0, 1)] {$terms.get(0)} $first_slot_value) slot*
    ->  // leading implicit tuple, followed by slots
        ^(TUPLE DEPSIGN["+"] {getTupleTree($terms, $terms.size() - 1)})
        // normalize to right-slot normal form
        ^(SLOT DEPSIGN[$SLOT_ARROW.text.substring(0, 1)] {$terms.get($terms.size() - 1)} $first_slot_value) slot*
    ;

tuple
    :   DEPSIGN LSQBR (term ({ checkPrecedingWhitespace(); } term)*)? RSQBR -> ^(TUPLE DEPSIGN term*)
    |   LSQBR (term ({ checkPrecedingWhitespace(); } term)*)? RSQBR -> ^(TUPLE DEPSIGN["+"] term*)    // Tuples with no dependency signs are treated as dependent, may be DEPRECATED in the future
    ;

slot
    :
        name=term SLOT_ARROW value=term -> ^(SLOT DEPSIGN[$SLOT_ARROW.text.substring(0, 1)] $name $value)
    ;

/*
**  The rule of constant strings can be rewritten to
**  Const ::= '"' UNICODESTRING '"' (^^ SYMSPACE))? | '"' UNICODESTRING '"@' langtag)? | CURIE | NumericLiteral | '_' NCName | IRI_REF
**  Symbol const_string is introduced to capture the first branch.
*/

constant
    :	iri   -> ^(SHORTCONST iri)
    |   const_string -> const_string
    |   NUMBER  -> ^(SHORTCONST NUMBER)
    |   { String localConstName; }
		PN_LOCAL {
    		if ($PN_LOCAL.text.startsWith("_"))
				localConstName = $PN_LOCAL.text.substring(1);
			else {
				if (m_config.reconstruct)
					localConstName = $PN_LOCAL.text; // Allow local constants without '_'-prefix
				else
					throw new PSOARuntimeException("Incorrect constant format:" + $PN_LOCAL.text);  // Enforcing '_' prefix
            }

            m_localConsts.add(localConstName);
        }
        -> ^(SHORTCONST LOCAL[localConstName])
    |   TOP
    ;


//  Complete and abbreviated string constant
const_string
@init
{
    boolean isAbbrivated = true;
}
    : STRING ((SYMSPACE_OPER symspace=iri { isAbbrivated = false; } ) | '@')?
    -> {isAbbrivated}? ^(SHORTCONST LITERAL[getStrValue($STRING.text)])
    -> { s_numberTypeIRIs.contains($symspace.fullIRI)}? ^(SHORTCONST NUMBER[getStrValue($STRING.text)])
    -> { fastStringEquals($symspace.fullIRI, s_stringIRI) }? ^(SHORTCONST LITERAL[getStrValue($STRING.text)])
    -> ^(LITERAL[getStrValue($STRING.text)] IRI[$symspace.text])
    //|   STRING '@' ID /* langtag */ -> ^(SHORTCONST LITERAL[$STRING.text])
    ;

variable
    :   VAR_ID -> VAR_ID[$VAR_ID.text.substring(1)]
    ;

answer
    : 'yes'
    | 'no'
    | (term EQUAL term)+
    ;

iri returns [String fullIRI]
	: IRI_REF -> IRI[$fullIRI = $IRI_REF.text]
	| curie { $fullIRI = $curie.fullIRI; }
	;

curie returns [String fullIRI]
	: NAMESPACE localName=PN_LOCAL
	-> { localName == null }? IRI[$fullIRI = getFullIRI($NAMESPACE.text, "")]
	-> IRI[$fullIRI = getFullIRI($NAMESPACE.text, $localName.text)]
	;

//--------------------- LEXER: -----------------------
// Comments and whitespace:
WHITESPACE  :  (' '|'\t'|'\r'|'\n')+ { $channel = HIDDEN; } ;
COMMENT : '%' ~('\n')* { $channel = HIDDEN; } ;
MULTI_LINE_COMMENT :  '<!--' (options {greedy=false;} : .* ) '-->'
                      { $channel=HIDDEN; }
                      {
                        if (printDeprecatedCommentWarning) {
                           System.out.println("Warning: XML-style comment blocks (delimited by '<!--'/'-->') are now deprecated and will be removed in a future release.");
                           printDeprecatedCommentWarning = false;
                        }
                      }
                   |  '/*' (options {greedy=false;} : .*) '*/' { $channel=HIDDEN; }	;

// Keywords:
DOCUMENT : 'Document' | 'RuleML' ;
BASE : 'Base' ;
IMPORT : 'Import' ;
PREFIX : 'Prefix' ;
GROUP : 'Group' | 'Assert' ;
FORALL : 'Forall' ;
EXISTS : 'Exists' ;
AND : 'And' ;
OR : 'Or' ;
NAF : 'Naf';
EXTERNAL : 'External';
TOP : 'Top';

//   Operators:
IMPLICATION : ':-';
EQUAL : '=';
SUBCLASS : '##';
INSTANCE : '#';
SLOT_ARROW : '->' | '+>';
SYMSPACE_OPER : '^^';

//   Punctuation:
LPAR : '(' ;
RPAR : ')' ;
LESS : '<' ;
GREATER : '>' ;
DEPSIGN: '+' | '-';
LSQBR : '[' ;
RSQBR : ']' ;


//  Constants:
NUMBER: ('+' | '-')? DIGIT+ ('.' DIGIT*)?;
STRING: '"' (options {greedy=false;} : ~('"' | '\\' | EOL) | ECHAR)* '"';

//  Identifiers:
// IRI_REF : '<' IRI_START_CHAR (IRI_CHAR)+ '>' { setText(getFullIRI(iri)); };

IRI_REF
    : '<' IRI_REF_CHAR* '>' { String s = getText(); setText(s.substring(1, s.length() - 1)); }
    ;

fragment IRI_REF_CHAR
    :  ~('<' | '>' | '"' | '{' | '}' | '|' | '^' | '`' | '\\' | '\u0000'..'\u0020')
    ;


// Modified from SPARQL 1.1
NAMESPACE : PN_PREFIX? ':';
fragment PN_PREFIX : PN_CHARS_BASE ((PN_CHARS|'.')* PN_CHARS)?;
PN_LOCAL
	: (PN_CHARS_U | DIGIT | PLX) (PN_CHARS | PLX)*;

fragment PN_CHARS
    : PN_CHARS_U
    | { input.LA(2) != '>' }? => '-'
    | DIGIT
    | '\u00B7'
    | '\u0300'..'\u036F'
    | '\u203F'..'\u2040'
    ;
fragment PN_CHARS_U : PN_CHARS_BASE | '_';
fragment PN_CHARS_BASE
    : ALPHA
    | '\u00C0'..'\u00D6'
    | '\u00D8'..'\u00F6'
    | '\u00F8'..'\u02FF'
    | '\u0370'..'\u037D'
    | '\u037F'..'\u1FFF'
    | '\u200C'..'\u200D'
    | '\u2070'..'\u218F'
    | '\u2C00'..'\u2FEF'
    | '\u3001'..'\uD7FF'
    | '\uF900'..'\uFDCF'
    | '\uFDF0'..'\uFFFD'
    ;

fragment PLX : PERCENT | PN_LOCAL_ESC;
fragment PERCENT : '%' HEX HEX;
fragment HEX : DIGIT | 'A'..'F' | 'a'..'f';
fragment PN_LOCAL_ESC
	:  '\\' ( '_' | '~' | '.' | '-' | '!' | '$' | '&' | '\'' | '(' | ')' | '*' | '+' | ','
			| ';' | '=' | ':' | '/' | '?' | '#' | '@' | '%' );

fragment ALPHA : 'a'..'z' | 'A'..'Z' ;
fragment DIGIT : '0'..'9' ;

VAR_ID : '?' PN_LOCAL?;

fragment ECHAR : '\\' ('t' | 'b' | 'n' | 'r' | 'f' | '\\' | '"' | '\'');

fragment EOL : '\n' | '\r';