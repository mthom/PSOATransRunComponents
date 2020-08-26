/* 
 * Java class for operating PSOA queries.
 * 
 * */

package org.ruleml.psoa;
import java.util.Set;

import org.antlr.runtime.ParserRuleReturnScope;
import org.antlr.runtime.RecognitionException;
import org.antlr.runtime.tree.Tree;
import org.ruleml.psoa.parser.PSOAPSParser;
import org.ruleml.psoa.transformer.*;
import org.ruleml.psoa.utils.ANTLRTreeStreamConsumer;

public class PSOAQuery extends PSOAInput<PSOAQuery>
{
	private PSOAKB m_kb;
	
	/**
     * the set of local constants
     * */
    private Set<String> m_localConsts;
	
//	public PSOAQuery() {
//		m_kb = null;
//	}
	
	public PSOAQuery(PSOAKB kb) {
		m_kb = kb;
	}
	
	@Override
	protected ParserRuleReturnScope parse(PSOAPSParser parser) throws RecognitionException {
	    ParserRuleReturnScope ret = parser.query(m_kb.getNamespaceTable());
	    m_localConsts = parser.getLocalConsts();
		return ret;
	}
	
	public PSOAQuery rename()
	{
		return transform("renaming", stream -> (new Renamer(stream)).query());
	}
	
	public PSOAQuery unnest()
	{
		return transform("unnesting", stream -> (new Unnester(stream)).query());
	}
	
	public PSOAQuery embeddedObjectify()
    {
        return transform("embedded objectification", stream -> {                        
            EmbeddedObjectifier objectifier = new EmbeddedObjectifier(stream);            
            objectifier.setExcludedLocalConstNames(m_localConsts);
            return objectifier.query();
        });
    }
	
	public PSOAQuery objectify(boolean differentiated, boolean dynamic)
	{
		PSOAQuery q;
		
		if (dynamic)
		{
			q = transform("rewriting for dynamic objectification", stream -> (new QueryRewriter(stream, m_kb.getKBInfo())).query());
		}
		else
			q = this;
		
		return q.transform("static objectification", stream -> {
			Objectifier objectifier = new Objectifier(stream);
			objectifier.setDynamic(dynamic, m_kb.getKBInfo());
			objectifier.setDifferentiated(differentiated);
			return objectifier.query();
		});
	}
	
	public PSOAQuery describute(boolean omitMemtermInNegativeAtoms)
	{
		return transform("describution", stream -> {
			Descributor descributor = new Descributor(stream);
			descributor.setOmitMemtermInNegativeAtoms(omitMemtermInNegativeAtoms);
			return descributor.query();
		});
	}
	
	public PSOAQuery flatten()
	{
		return transform("flattening", stream -> (new ExternalFlattener(stream)).query());
	}
	
	@Override
	public PSOAQuery transform(String name, ANTLRTreeStreamConsumer actor, boolean newKBInst)
	{
		try
		{
			if (newKBInst)
			{
				/* TODO: Create new instance */
				return null;
			}
			else
			{
				m_tree = (Tree) actor.apply(getTreeNodeStream()).getTree();
				if (m_printAfterTransformation)
				{
					m_printStream.println(String.format("After %s :", name));
					printTree();
				}
				return this;
			}
		}
		catch (RecognitionException e)
		{
			String msg = String.format("Failed to parse input for %s transformation", name);
			throw new PSOATransformerException(msg, e);
		}
	}
	
	
	/**
	 * Perform FOL-targeting normalization of a PSOA query
	 * 
	 * @param config   transformer configuration
	 * 
	 * @return the FOL-normalized PSOA query
	 * 
	 * */
	@Override
	public PSOAQuery FOLnormalize(RelationalTransformerConfig config) {
		return embeddedObjectify().
		       unnest().
			   objectify(config.differentiateObj, config.dynamicObj).
			   describute(config.omitMemtermInNegativeAtoms);
	}

	
	/**
	 * Perform LP-targeting normalization of a PSOA query
	 * 
	 * @param config   transformer configuration
	 * 
	 * @return   the LP-normalized PSOA query
	 * 
	 * */
	@Override
	public PSOAQuery LPnormalize(RelationalTransformerConfig config) {
		return FOLnormalize(config).
			   flatten();
	}
}
