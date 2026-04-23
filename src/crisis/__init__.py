"""
Crisis: Probabilistically Self Organizing Total Order in Unstructured P2P Networks

A Python implementation of the Crisis protocol described by Mirco Richter (2019).

The protocol achieves total order on messages in fully open, unstructured
Peer-to-Peer networks through virtual voting -- votes are never sent explicitly
but are deduced from the causal relationships between messages encoded in
Lamport graphs.

Key components:
    - crypto:   Random oracle model (SHA-256 hash function)
    - message:  Message and Vertex data structures
    - weight:   Weight systems (PoW-based Sybil resistance)
    - graph:    Lamport graphs with integrity checking
    - rounds:   Virtual synchronous rounds
    - voting:   Safe voting patterns and virtual leader election (BA*)
    - order:    Total order via leader stream and topological sorting
    - gossip:   Push/pull gossip for member discovery and message dissemination
    - node:     Full Crisis node tying all components together
"""
